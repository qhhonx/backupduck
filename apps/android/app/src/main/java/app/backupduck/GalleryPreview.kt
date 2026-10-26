package app.backupduck

import android.content.ContentUris
import android.content.Context
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.CancellationSignal
import android.provider.MediaStore
import android.util.Size
import org.json.JSONObject
import kotlin.math.min
import kotlin.math.max

internal data class GalleryPreviewCopy(val uri:Uri,val mime:String,val durationMs:Long?)

/** Read the real published copy independently of thumbnail availability. No writes. */
internal object GalleryPreview {
    fun resolve(context:Context,item:HistoryItem,preferred:Uri?,signal:CancellationSignal):GalleryPreviewCopy? {
        if(item.processing!="complete") return null
        val resolver=context.contentResolver
        fun read(uri:Uri?):GalleryPreviewCopy? {
            if(uri?.scheme!="content"||uri.authority!="media")return null
            signal.throwIfCanceled()
            return runCatching {
                resolver.query(uri,arrayOf(MediaStore.MediaColumns.MIME_TYPE,MediaStore.MediaColumns.IS_PENDING,MediaStore.MediaColumns.SIZE),null,null,null,signal)?.use { c ->
                    if(!c.moveToFirst()||c.getInt(1)!=0||(!c.isNull(2)&&c.getLong(2)<=0))return@use null
                    val mime=c.getString(0) ?: resolver.getType(uri) ?: if(item.kind=="video")"video/mp4" else "image/jpeg"
                    if(!mime.startsWith("image/")&&!mime.startsWith("video/"))return@use null
                    val duration=if(mime.startsWith("video/"))resolver.query(uri,arrayOf(MediaStore.Video.Media.DURATION),null,null,null,signal)?.use { d -> if(d.moveToFirst()&&!d.isNull(0))d.getLong(0).takeIf {it>0} else null } else null
                    GalleryPreviewCopy(uri,mime,duration)
                }
            }.getOrNull()
        }
        read(preferred)?.let {return it}
        val stored=runCatching {val e=NativeBridge.request(JSONObject().put("op","gallery_evidence").put("id",item.id)) as JSONObject;e.optJSONObject("copy")?.optString("locator")?.takeIf {it.isNotBlank()}?.let(Uri::parse)}.getOrNull()
        read(stored)?.let {return it}
        // Only exact legacy names in our own delivery folder; no broad filename
        // matching that might mistake a user's unrelated media for this asset.
        val collection=if(item.kind=="video")MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val uri=resolver.query(collection,arrayOf(MediaStore.MediaColumns._ID),
            "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ? AND ${MediaStore.MediaColumns.RELATIVE_PATH}=? AND ${MediaStore.MediaColumns.IS_PENDING}=0",
            arrayOf("BD_${item.id}.%","DCIM/BackupDuck/"),null,signal)?.use {c ->if(c.moveToFirst())ContentUris.withAppendedId(collection,c.getLong(0)) else null}
        return read(uri)
    }
    fun decode(context:Context,copy:GalleryPreviewCopy,target:Size,signal:CancellationSignal):Bitmap {
        signal.throwIfCanceled()
        val result=if(copy.mime.startsWith("image/")) {
            ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver,copy.uri)) {decoder,info,_->
                val fraction=min(1.0,max(target.width.toDouble()/info.size.width,target.height.toDouble()/info.size.height))
                decoder.setTargetSize((info.size.width*fraction).toInt().coerceAtLeast(1),(info.size.height*fraction).toInt().coerceAtLeast(1))
                decoder.allocator=ImageDecoder.ALLOCATOR_SOFTWARE
            }
        } else {
            runCatching {
                context.contentResolver.loadThumbnail(copy.uri,target,signal)
            }.getOrElse {
                signal.throwIfCanceled()
                MediaMetadataRetriever().use {r ->
                    signal.throwIfCanceled();r.setDataSource(context,copy.uri)
                    val width=r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: target.width
                    val height=r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: target.height
                    val fraction=min(1.0,max(target.width.toDouble()/width,target.height.toDouble()/height))
                    checkNotNull(r.getScaledFrameAtTime(0,MediaMetadataRetriever.OPTION_CLOSEST_SYNC,(width*fraction).toInt().coerceAtLeast(1),(height*fraction).toInt().coerceAtLeast(1)))
                }
            }
        }
        signal.throwIfCanceled();return result
    }
}
