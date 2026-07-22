use crate::atomic;
use crate::error::{invalid_path, AppError, Result};
use base64::Engine;
use image::{DynamicImage, GenericImageView, ImageFormat};
use std::fs;
use std::io::Cursor;
use std::path::{Path, PathBuf};
use uuid::Uuid;

const MAX_BYTES: u64 = 16 * 1024 * 1024;
const MAX_PIXELS: u64 = 40_000_000;

#[derive(Clone, Debug)]
pub struct ImportedImage {
    pub name: String,
    pub suggested_accent: Option<String>,
}

#[derive(Clone)]
pub struct ImageStore {
    directory: PathBuf,
}

impl ImageStore {
    pub fn new(support: &Path) -> Self {
        Self {
            directory: support.join("Backgrounds"),
        }
    }

    pub fn import(&self, source: &Path) -> Result<ImportedImage> {
        let metadata = fs::symlink_metadata(source)
            .map_err(|error| AppError::path("读取图片属性", source, error))?;
        if !metadata.file_type().is_file() || metadata.file_type().is_symlink() {
            return Err(invalid_path(source.to_path_buf()));
        }
        if metadata.len() == 0 || metadata.len() > MAX_BYTES {
            return Err(AppError::InvalidImage("图片大小必须在 16 MB 以内".into()));
        }
        let bytes = fs::read(source).map_err(|error| AppError::path("读取图片", source, error))?;
        let image = image::load_from_memory(&bytes).map_err(|_| {
            AppError::InvalidImage("仅支持可完整解码的 PNG、JPEG、TIFF 或 WebP".into())
        })?;
        validate_dimensions(&image)?;
        let accent = suggested_accent(&image);
        let mut normalized = Vec::new();
        image
            .write_to(&mut Cursor::new(&mut normalized), ImageFormat::Png)
            .map_err(|error| AppError::InvalidImage(format!("无法规范化 PNG：{error}")))?;
        if normalized.len() as u64 > MAX_BYTES {
            return Err(AppError::InvalidImage("规范化后的 PNG 超过 16 MB".into()));
        }
        let name = format!("background-{}.png", Uuid::new_v4());
        atomic::write_private(&self.directory.join(&name), &normalized)?;
        Ok(ImportedImage {
            name,
            suggested_accent: accent,
        })
    }

    pub fn copy(&self, name: Option<&str>) -> Result<Option<String>> {
        let Some(name) = name else { return Ok(None) };
        let source = self
            .resolve(Some(name))
            .ok_or_else(|| AppError::InvalidImage("已选择的图片不存在，请重新选择".into()))?;
        let data =
            fs::read(&source).map_err(|error| AppError::path("读取背景图片", &source, error))?;
        if data.len() as u64 > MAX_BYTES {
            return Err(AppError::InvalidImage("背景图片超过 16 MB".into()));
        }
        let target_name = format!("background-{}.png", Uuid::new_v4());
        atomic::write_private(&self.directory.join(&target_name), &data)?;
        Ok(Some(target_name))
    }

    pub fn remove(&self, name: Option<&str>) -> Result<()> {
        if let Some(path) = self.resolve(name) {
            fs::remove_file(&path).map_err(|error| AppError::path("删除背景图片", &path, error))?;
        }
        Ok(())
    }

    pub fn resolve(&self, name: Option<&str>) -> Option<PathBuf> {
        let name = name?;
        if Path::new(name).file_name().and_then(|value| value.to_str()) != Some(name) {
            return None;
        }
        let path = self.directory.join(name);
        let metadata = fs::symlink_metadata(&path).ok()?;
        (metadata.file_type().is_file() && !metadata.file_type().is_symlink()).then_some(path)
    }

    pub fn data_url(&self, name: Option<&str>) -> Result<Option<String>> {
        let Some(path) = self.resolve(name) else {
            return Ok(None);
        };
        let data = fs::read(&path).map_err(|error| AppError::path("读取背景图片", &path, error))?;
        Ok(Some(format!(
            "data:image/png;base64,{}",
            base64::engine::general_purpose::STANDARD.encode(data)
        )))
    }
}

fn validate_dimensions(image: &DynamicImage) -> Result<()> {
    let (width, height) = image.dimensions();
    let pixels = u64::from(width) * u64::from(height);
    if width < 320 || height < 240 || width > 16_384 || height > 16_384 || pixels > MAX_PIXELS {
        return Err(AppError::InvalidImage(
            "尺寸至少为 320x240，单边不超过 16384，像素总量不超过 4000 万".into(),
        ));
    }
    Ok(())
}

fn suggested_accent(image: &DynamicImage) -> Option<String> {
    let sample = image.thumbnail_exact(48, 48).to_rgba8();
    let best = sample
        .pixels()
        .filter(|pixel| pixel[3] >= 128)
        .filter_map(|pixel| {
            let red = f64::from(pixel[0]) / 255.0;
            let green = f64::from(pixel[1]) / 255.0;
            let blue = f64::from(pixel[2]) / 255.0;
            let maximum = red.max(green).max(blue);
            let minimum = red.min(green).min(blue);
            let saturation = if maximum == 0.0 {
                0.0
            } else {
                (maximum - minimum) / maximum
            };
            let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue;
            (saturation >= 0.25 && (0.16..=0.88).contains(&luminance)).then_some((
                pixel[0],
                pixel[1],
                pixel[2],
                saturation * (1.0 - (luminance - 0.55).abs()),
            ))
        })
        .max_by(|left, right| left.3.total_cmp(&right.3))?;
    Some(format!("#{:02X}{:02X}{:02X}", best.0, best.1, best.2))
}
