//! Pixel-specific output planning. No Pixel policies leak into transport.
//! A native Android host must implement conversion and MediaStore publication.
mod burst;
mod gain_map;
mod heic_motion;
mod motion_xmp;
mod photo_date;
pub use photo_date::write_photo_date;
pub mod photos_cleanup;
pub mod photos_probe;
pub mod storage;
use backupduck_core::{
    Asset, AssetKind, BurstMetadata, Error, Result, TargetPlan, TargetProcessor,
};
pub use burst::write_jpeg_burst;
pub use heic_motion::write_heic_motion_with_burst;
pub use heic_motion::write_heic_motion_with_burst_and_video_mime;

#[derive(Default)]
pub struct PixelTarget {
    pub motion_conversion_available: bool,
}
impl TargetProcessor for PixelTarget {
    fn plan(&self, asset: &Asset) -> Result<TargetPlan> {
        asset.validate()?;
        match asset.kind {
            AssetKind::Motion if !self.motion_conversion_available => {
                Err(Error::Unsupported("pixel.motion_photo".into()))
            }
            AssetKind::Motion => Ok(TargetPlan::GenerateMotionPhoto),
            AssetKind::Photo if BurstMetadata::from_fields(&asset.metadata)?.is_some() => {
                Ok(TargetPlan::GenerateBurstPhoto)
            }
            _ => Ok(TargetPlan::PublishOriginals),
        }
    }
}

/// Package a native-decoded JPEG and native-encoded MP4 into a Motion Photo.
/// Original resources remain in the receiver store. The host owns codec support;
/// this function owns the container layout. None uses the format's midpoint rule.
pub fn write_jpeg_motion(
    jpeg: &std::path::Path,
    mp4: &std::path::Path,
    output: &std::path::Path,
    timestamp_us: Option<u64>,
) -> backupduck_core::Result<()> {
    write_jpeg_motion_with_burst(jpeg, mp4, output, timestamp_us, None)
}
pub fn write_jpeg_motion_with_burst(
    jpeg: &std::path::Path,
    mp4: &std::path::Path,
    output: &std::path::Path,
    timestamp_us: Option<u64>,
    burst: Option<&BurstMetadata>,
) -> Result<()> {
    write_jpeg_motion_with_burst_and_video_mime(jpeg, mp4, output, timestamp_us, burst, "video/mp4")
}

/// Package a JPEG and an already-compatible MP4 or QuickTime MOV without
/// decoding either resource. The declared MIME must match the supplied video.
pub fn write_jpeg_motion_with_burst_and_video_mime(
    jpeg: &std::path::Path,
    mp4: &std::path::Path,
    output: &std::path::Path,
    timestamp_us: Option<u64>,
    burst: Option<&BurstMetadata>,
    video_mime: &str,
) -> Result<()> {
    if !matches!(video_mime, "video/mp4" | "video/quicktime") {
        return Err(Error::Unsupported("motion video MIME".into()));
    }
    if jpeg == output
        || mp4 == output
        || (output.exists()
            && (jpeg.canonicalize()? == output.canonicalize()?
                || mp4.canonicalize()? == output.canonicalize()?))
    {
        return Err(Error::Invalid("motion delivery destination".into()));
    }
    if let Some(burst) = burst {
        burst.validate()?;
    }
    let burst_fields = burst
        .map(|b| {
            format!(
                " GCamera:BurstID=\"{}\" GCamera:BurstPrimary=\"{}\"",
                b.group_id,
                if b.primary { 1 } else { 0 }
            )
        })
        .unwrap_or_default();
    use backupduck_core::{Error, Result};
    use std::{
        fs::{File, OpenOptions},
        io::{Seek, SeekFrom, Write},
    };
    const XMP: &[u8] = b"http://ns.adobe.com/xap/1.0/\0";
    let mut still = std::fs::read(jpeg)?;
    if !still.starts_with(&[0xff, 0xd8]) {
        return Err(Error::Unsupported("motion JPEG input".into()));
    }
    // The native codec provides a clean JPEG, except that Android 14+ keeps a
    // decoded gain map and writes Ultra HDR. Merge into that GContainer
    // directory and keep MPF geometry valid; never create a second XMP packet.
    let (mut old, mut mpf, mut at) = (None, None, 2usize);
    loop {
        let header = still.get(at..at + 4).ok_or(Error::Integrity)?;
        if header[0] != 0xff {
            return Err(Error::Integrity);
        }
        if header[1] == 0xda {
            break;
        }
        if header[1] == 0xd9 || header[1] == 0 || header[1] == 0xff {
            return Err(Error::Integrity);
        }
        let (marker, length) = (
            header[1],
            u16::from_be_bytes([header[2], header[3]]) as usize,
        );
        if length < 2 {
            return Err(Error::Integrity);
        }
        let payload = at + 4..at + 2 + length;
        let segment = still.get(payload.clone()).ok_or(Error::Integrity)?;
        if marker == 0xe1 && segment.starts_with(XMP) {
            if old.is_some() {
                return Err(Error::Unsupported("preexisting XMP packet".into()));
            }
            old = Some(at..payload.end);
        }
        if marker == 0xe1 && segment.starts_with(b"http://ns.adobe.com/xmp/extension/\0") {
            return Err(Error::Unsupported("extended XMP packet".into()));
        }
        if marker == 0xe2 && segment.starts_with(b"MPF\0") {
            if mpf.is_some() {
                return Err(Error::Unsupported("multi-picture JPEG".into()));
            }
            mpf = Some(gain_map::Mpf::parse(&still, payload.clone())?);
        }
        at = payload.end;
    }
    let mut auxiliary_start = None;
    let gain = match (&old, &mpf) {
        (Some(range), Some(mpf)) => {
            let parsed_gain = gain_map::directory(&still[range.start + 4 + XMP.len()..range.end]);
            let layout = || Error::Unsupported("Ultra HDR JPEG layout".into());
            if mpf.count != 2 {
                return Err(layout());
            }
            let map = mpf.entry(&still, 1);
            // Locate the primary image by the gain map offset, not the primary size
            // entry: androidx ExifInterface inserts EXIF after Bitmap.compress without
            // updating MPF, so that size can be stale while the offset (relative to
            // the MP header, which moved too) stays exact. Container items are laid
            // out in order: the gain map must follow the primary and end the file.
            let primary = mpf.header + map.offset as usize;
            if primary + map.size as usize != still.len()
                || !still[primary..].starts_with(&[0xff, 0xd8])
                || !still[..primary].ends_with(&[0xff, 0xd9])
            {
                return Err(layout());
            }
            auxiliary_start = Some(primary);
            match parsed_gain {
                Ok(gain) if u64::from(map.size) == gain.length => Some((gain, primary)),
                Ok(_) => return Err(layout()),
                Err(_) => None,
            }
        }
        _ => None,
    };
    let mut video = File::open(mp4)?;
    let video_len = video.metadata()?.len();
    validate_motion_video(&mut video, video_len, video_mime)?;
    video.seek(SeekFrom::Start(0))?;
    let time = timestamp_us
        .map(|v| format!(" GCamera:MotionPhotoPresentationTimestampUs=\"{v}\""))
        .unwrap_or_default();
    let primary_end = auxiliary_start;
    let (hdr_ns, hdr_version) = gain.as_ref().map_or_else(
        || ("", String::new()),
        |(g, _)| {
            (
                r#" xmlns:hdrgm="http://ns.adobe.com/hdr-gain-map/1.0/""#,
                format!(r#" hdrgm:Version="{}""#, g.version),
            )
        },
    );
    // MPF's second JPEG is part of the container even when the source has
    // ordinary Apple XMP rather than Android's Ultra HDR directory. Leaving it
    // out makes the declared video location disagree with the actual layout.
    let gain_item = auxiliary_start
        .map(|start| {
            format!(
                r#"<rdf:li rdf:parseType="Resource"><Container:Item Item:Mime="image/jpeg" Item:Semantic="GainMap" Item:Length="{}"/></rdf:li>"#,
                still.len() - start
            )
        })
        .unwrap_or_default();
    let xmp = format!(
        r#"<rdf:Description xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" rdf:about="" xmlns:GCamera="http://ns.google.com/photos/1.0/camera/" xmlns:Container="http://ns.google.com/photos/1.0/container/" xmlns:Item="http://ns.google.com/photos/1.0/container/item/"{hdr_ns} GCamera:MotionPhoto="1" GCamera:MotionPhotoVersion="1"{time}{burst_fields}{hdr_version}><Container:Directory><rdf:Seq><rdf:li rdf:parseType="Resource"><Container:Item Item:Mime="image/jpeg" Item:Semantic="Primary" Item:Length="0"/></rdf:li>{gain_item}<rdf:li rdf:parseType="Resource"><Container:Item Item:Mime="{video_mime}" Item:Semantic="MotionPhoto" Item:Length="{video_len}"/></rdf:li></rdf:Seq></Container:Directory></rdf:Description>"#
    );
    let xmp = match (&old, &gain) {
        (Some(range), None) => motion_xmp::merge(
            &still[range.start + 4 + XMP.len()..range.end],
            xmp.as_bytes(),
        )?,
        _ => format!(r#"<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">{xmp}</rdf:RDF></x:xmpmeta>"#).into_bytes(),
    };
    let mut packet = XMP.to_vec();
    packet.extend(xmp);
    let size: u16 = (packet.len() + 2).try_into().map_err(|_| Error::Capacity)?;
    // Secondary MPF images are addressed relative to the MP header. The new
    // packet precedes it; a removed packet only moves offsets if it followed it.
    if let Some(mpf) = &mpf {
        let removed = old.as_ref().map_or(0, |r| r.len());
        let added = 4 + packet.len();
        let primary = primary_end.unwrap_or(mpf.entry(&still, 0).size as usize);
        let size = u32::try_from(primary + added - removed).map_err(|_| Error::Capacity)?;
        let moved = match &old {
            Some(r) if r.start > mpf.header => -(removed as i64),
            _ => 0,
        };
        mpf.rebase(&mut still, size, moved)?;
    }
    let partial = output.with_extension("motion.partial");
    let mut out = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&partial)?;
    let result = (|| -> Result<()> {
        out.write_all(&[0xff, 0xd8, 0xff, 0xe1])?;
        out.write_all(&size.to_be_bytes())?;
        out.write_all(&packet)?;
        match &old {
            Some(r) => {
                out.write_all(&still[2..r.start])?;
                out.write_all(&still[r.end..])?;
            }
            None => out.write_all(&still[2..])?,
        }
        std::io::copy(&mut video, &mut out)?;
        out.sync_all()?;
        drop(out);
        std::fs::rename(&partial, output)?;
        Ok(())
    })();
    if result.is_err() {
        let _ = std::fs::remove_file(&partial);
    }
    result
}

/// Older iPhone paired QuickTime movies can have no `ftyp` box at all. Their
/// complete top-level layout is `wide` + `mdat` + `moov`; rejecting them here
/// needlessly sends the receiver into its lossy compatibility conversion.
fn validate_motion_video(video: &mut std::fs::File, length: u64, mime: &str) -> Result<()> {
    use std::io::{Read, Seek, SeekFrom};

    let unsupported = || Error::Unsupported("motion video container".into());
    if length < 16 {
        return Err(unsupported());
    }
    let mut header = [0u8; 8];
    video.read_exact(&mut header)?;
    if &header[4..8] == b"ftyp" {
        return Ok(());
    }
    if mime != "video/quicktime" || header != *b"\0\0\0\x08wide" {
        return Err(unsupported());
    }
    let mut offset = 8u64;
    for expected in [b"mdat", b"moov"] {
        video.seek(SeekFrom::Start(offset))?;
        video.read_exact(&mut header).map_err(|_| unsupported())?;
        let size = u64::from(u32::from_be_bytes(header[..4].try_into().unwrap()));
        if header[4..8] != *expected || size <= 8 {
            return Err(unsupported());
        }
        offset = offset.checked_add(size).ok_or_else(unsupported)?;
        if offset > length {
            return Err(unsupported());
        }
    }
    if offset != length {
        return Err(unsupported());
    }
    Ok(())
}
