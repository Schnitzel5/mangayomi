use crate::api::colorizer::{colorize::colorize, types::AppConfig, utils::hex_to_rgb};

use std::io::Cursor;

use anyhow::Result;
use palette::{FromColor, Lab};

pub fn load_colorscheme(colors: Vec<String>) -> Vec<Lab> {
    return colors
        .iter()
        .map(|hex| Lab::from_color(hex_to_rgb(hex).unwrap()))
        .collect();
}

pub async fn colorize_image(image: Vec<u8>, config: AppConfig) -> Result<Vec<u8>> {
    let decoded_image =
        image::load_from_memory(image.as_slice()).expect(&format!("Failed to load image"));
    let final_output = colorize(&decoded_image, &config).await.unwrap();
    let mut image_data: Vec<u8> = Vec::new();
    final_output
        .write_to(&mut Cursor::new(&mut image_data), image::ImageFormat::Png)
        .unwrap();
    return Ok(image_data);
}
