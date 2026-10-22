package app.backupduck

import org.junit.Assert.*
import org.junit.Test
import java.util.Locale

class PhotoMetadataTest {
    @Test fun recordedCaptureUsesStableOrderAndDoesNotRoundExposureToAnotherShutterSpeed() {
        assertEquals("ƒ/1.78 · 1/120 s · 6.8 mm · 24 mm (35 mm) · ISO 80",
            PhotoMetadata(aperture = 1.78, exposure = 1.0 / 120, focal = 6.8, equivalent = 24, iso = 80).capture(Locale.US)?.replace('\u00a0', ' '))
        assertEquals("0.0083 s", PhotoMetadata(exposure = .0083).capture(Locale.US)?.replace('\u00a0', ' '))
        assertEquals("0.33333 s", PhotoMetadata(exposure = .33333).capture(Locale.US)?.replace('\u00a0', ' '))
        assertEquals("2 s", PhotoMetadata(exposure = 2.0).capture(Locale.US)?.replace('\u00a0', ' '))
    }
    @Test fun absentCaptureStaysAbsentAndCameraDoesNotRepeatBrand() {
        assertNull(PhotoMetadata().capture(Locale.US)?.replace('\u00a0', ' '))
        assertEquals("iPhone 15 Pro", photoCameraName("Apple", "iPhone 15 Pro"))
        assertEquals("Canon EOS 6D", photoCameraName("Canon", "Canon EOS 6D"))
        assertEquals("Panasonic DMC-G7", photoCameraName("Panasonic", "DMC-G7"))
        assertEquals("NIKON D5200", photoCameraName("NIKON CORPORATION", "NIKON D5200"))
        assertNull(photoCameraName(null, null))
    }
    @Test fun videoDurationKeepsRecordedFractions() {
        assertEquals("00:03", photoDuration(3000))
        assertEquals("00:00.125", photoDuration(125))
        assertEquals("1:01:02.5", photoDuration(3662500))
    }
}
