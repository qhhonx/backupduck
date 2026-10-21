//! Use Android's installed codecs through the existing JNI dependency. No
//! MediaStore, permissions, subprocesses, network, or bundled codec libraries.
use super::*;
use jni::{objects::JValue, JavaVM};

static VM: OnceLock<JavaVM> = OnceLock::new();
pub(crate) fn remember_vm(env: &jni::JNIEnv) {
    if let Ok(vm) = env.get_java_vm() {
        let _ = VM.set(vm);
    }
}

pub(super) fn decode(source: &Path) -> Option<Vec<u8>> {
    let mut env = VM.get()?.attach_current_thread().ok()?;
    let result = env.with_local_frame(48, |env| -> jni::errors::Result<Option<Vec<u8>>> {
        let path = env.new_string(source.to_string_lossy())?;
        let options = env.new_object("android/graphics/BitmapFactory$Options", "()V", &[])?;
        env.set_field(&options, "inJustDecodeBounds", "Z", JValue::Bool(1))?;
        env.call_static_method(
            "android/graphics/BitmapFactory", "decodeFile",
            "(Ljava/lang/String;Landroid/graphics/BitmapFactory$Options;)Landroid/graphics/Bitmap;",
            &[JValue::Object(&path), JValue::Object(&options)],
        )?;
        let width = env.get_field(&options, "outWidth", "I")?.i()?;
        let height = env.get_field(&options, "outHeight", "I")?.i()?;
        if width <= 0 || height <= 0 || width > 65536 || height > 65536 {
            return Ok(None);
        }
        let mut sample = 1;
        while width.max(height) / sample > LONG_EDGE as i32 * 2 {
            sample *= 2;
        }
        env.set_field(&options, "inSampleSize", "I", JValue::Int(sample))?;
        env.set_field(&options, "inJustDecodeBounds", "Z", JValue::Bool(0))?;
        let bitmap = env.call_static_method(
            "android/graphics/BitmapFactory", "decodeFile",
            "(Ljava/lang/String;Landroid/graphics/BitmapFactory$Options;)Landroid/graphics/Bitmap;",
            &[JValue::Object(&path), JValue::Object(&options)],
        )?.l()?;
        if bitmap.is_null() {
            return Ok(None);
        }
        // All exits after decode recycle the native pixel allocation, including
        // exceptions during EXIF/transform/compression.
        let encoded = (|| -> jni::errors::Result<Option<Vec<u8>>> {
            let w = env.call_method(&bitmap, "getWidth", "()I", &[])?.i()?;
            let h = env.call_method(&bitmap, "getHeight", "()I", &[])?.i()?;
            if w <= 0 || h <= 0 || w.max(h) > LONG_EDGE as i32 * 2 + 1 {
                return Ok(None);
            }
            let scale = (LONG_EDGE as f32 / w.max(h) as f32).min(1.0);
            let matrix = env.new_object("android/graphics/Matrix", "()V", &[])?;
            env.call_method(&matrix, "postScale", "(FF)Z", &[JValue::Float(scale), JValue::Float(scale)])?;
            // Older Android releases cannot read PNG EXIF even when their pixel
            // codec works. Missing/unsupported EXIF must not discard the image.
            let orientation = (|| -> jni::errors::Result<i32> {
                let exif = env.new_object("android/media/ExifInterface", "(Ljava/lang/String;)V", &[JValue::Object(&path)])?;
                let tag = env.new_string("Orientation")?;
                env.call_method(&exif, "getAttributeInt", "(Ljava/lang/String;I)I", &[JValue::Object(&tag), JValue::Int(1)])?.i()
            })().unwrap_or(1);
            if env.exception_check()? { env.exception_clear()?; }
            let rotation = match orientation { 3 | 4 => 180.0, 6 | 7 => 90.0, 5 | 8 => 270.0, _ => 0.0 };
            if matches!(orientation, 2 | 4 | 5 | 7) {
                env.call_method(&matrix, "postScale", "(FF)Z", &[JValue::Float(-1.0), JValue::Float(1.0)])?;
            }
            env.call_method(&matrix, "postRotate", "(F)Z", &[JValue::Float(rotation)])?;
            let small = env.call_static_method(
                "android/graphics/Bitmap", "createBitmap",
                "(Landroid/graphics/Bitmap;IIIILandroid/graphics/Matrix;Z)Landroid/graphics/Bitmap;",
                &[JValue::Object(&bitmap), JValue::Int(0), JValue::Int(0), JValue::Int(w), JValue::Int(h), JValue::Object(&matrix), JValue::Bool(1)],
            )?.l()?;
            let result = (|| -> jni::errors::Result<Option<Vec<u8>>> {
                let w = env.call_method(&small, "getWidth", "()I", &[])?.i()?;
                let h = env.call_method(&small, "getHeight", "()I", &[])?.i()?;
                if w <= 0 || h <= 0 || w.max(h) > LONG_EDGE as i32 {
                    return Ok(None);
                }
                let output = env.new_object("java/io/ByteArrayOutputStream", "()V", &[])?;
                let jpeg = env.get_static_field("android/graphics/Bitmap$CompressFormat", "JPEG", "Landroid/graphics/Bitmap$CompressFormat;")?.l()?;
                let success = env.call_method(&small, "compress", "(Landroid/graphics/Bitmap$CompressFormat;ILjava/io/OutputStream;)Z", &[JValue::Object(&jpeg), JValue::Int(80), JValue::Object(&output)])?.z()?;
                if !success { return Ok(None); }
                let bytes = env.call_method(&output, "toByteArray", "()[B", &[])?.l()?;
                Ok(Some(env.convert_byte_array(jni::objects::JByteArray::from(bytes))?))
            })();
            if env.exception_check()? { env.exception_clear()?; }
            // createBitmap can return the input for an identity transform.
            if !env.is_same_object(&small, &bitmap)? {
                let _ = env.call_method(&small, "recycle", "()V", &[]);
            }
            result
        })();
        if env.exception_check()? { env.exception_clear()?; }
        let _ = env.call_method(&bitmap, "recycle", "()V", &[]);
        encoded
    });
    // Unsupported/corrupt formats and codec failures must not leave a pending
    // Java exception that would break construction of the JSON reply.
    if env.exception_check().unwrap_or(false) {
        let _ = env.exception_clear();
    }
    result.ok().flatten()
}
