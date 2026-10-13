use std::collections::HashMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Rgb8 {
    pub r: u8,
    pub g: u8,
    pub b: u8,
}

pub const FALLBACK: [Rgb8; 3] = [
    Rgb8 { r: 72, g: 76, b: 94 },
    Rgb8 { r: 46, g: 50, b: 64 },
    Rgb8 { r: 28, g: 30, b: 40 },
];

struct Bucket {
    hue: f64,
    order: usize,
    weight: f64,
    red: f64,
    green: f64,
    blue: f64,
}

fn rgb_to_hsv(red: f64, green: f64, blue: f64) -> (f64, f64, f64) {
    let max_value = red.max(green).max(blue);
    let min_value = red.min(green).min(blue);
    let delta = max_value - min_value;
    let mut hue = 0.0;
    if delta != 0.0 {
        hue = if max_value == red {
            ((green - blue) / delta) % 6.0
        } else if max_value == green {
            (blue - red) / delta + 2.0
        } else {
            (red - green) / delta + 4.0
        };
        hue *= 60.0;
        if hue < 0.0 {
            hue += 360.0;
        }
    }
    let saturation = if max_value == 0.0 { 0.0 } else { delta / max_value };
    (hue, saturation, max_value / 255.0)
}

fn hsv_to_rgb(hue: f64, saturation: f64, value: f64) -> Rgb8 {
    let chroma = value * saturation;
    let wrapped = ((hue % 360.0) + 360.0) % 360.0;
    let section = wrapped / 60.0;
    let x = chroma * (1.0 - (section % 2.0 - 1.0).abs());
    let base = value - chroma;
    let table = [
        [chroma, x, 0.0],
        [x, chroma, 0.0],
        [0.0, chroma, x],
        [0.0, x, chroma],
        [x, 0.0, chroma],
        [chroma, 0.0, x],
    ];
    let pick = table[(section.floor() as usize).min(5)];
    let byte = |component: f64| ((component + base) * 255.0 + 0.5).floor() as i64;
    Rgb8 { r: byte(pick[0]).clamp(0, 255) as u8, g: byte(pick[1]).clamp(0, 255) as u8, b: byte(pick[2]).clamp(0, 255) as u8 }
}

fn hue_distance(a: f64, b: f64) -> f64 {
    let diff = (a - b).abs() % 360.0;
    if diff > 180.0 {
        360.0 - diff
    } else {
        diff
    }
}

pub fn extract(rgba: &[u8]) -> Vec<Rgb8> {
    let mut buckets: HashMap<i64, Bucket> = HashMap::new();
    let mut gray_total = 0.0;
    let mut gray_count = 0.0;
    let mut order = 0usize;
    for pixel in rgba.chunks_exact(4) {
        let red = pixel[0] as f64;
        let green = pixel[1] as f64;
        let blue = pixel[2] as f64;
        let (hue, saturation, value) = rgb_to_hsv(red, green, blue);
        if value < 0.1 {
            continue;
        }
        if saturation < 0.18 {
            gray_total += (red + green + blue) / 3.0;
            gray_count += 1.0;
            continue;
        }
        let key = (hue / 20.0).floor() as i64 * 100 + (saturation * 3.0).floor() as i64 * 10 + (value * 3.0).floor() as i64;
        let weight = saturation * (0.4 + value) + 0.05;
        let bucket = buckets.entry(key).or_insert_with(|| {
            order += 1;
            Bucket { hue, order, weight: 0.0, red: 0.0, green: 0.0, blue: 0.0 }
        });
        bucket.weight += weight;
        bucket.red += red * weight;
        bucket.green += green * weight;
        bucket.blue += blue * weight;
        bucket.hue = hue;
    }
    let mut ranked: Vec<&Bucket> = buckets.values().collect();
    ranked.sort_by(|a, b| {
        b.weight
            .partial_cmp(&a.weight)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then(a.order.cmp(&b.order))
    });
    let Some(primary) = ranked.first() else {
        if gray_count == 0.0 {
            return FALLBACK.to_vec();
        }
        let level = (gray_total / gray_count / 255.0 / 2.2).clamp(0.22, 0.42);
        return vec![hsv_to_rgb(230.0, 0.08, level), hsv_to_rgb(230.0, 0.08, level * 0.62), hsv_to_rgb(230.0, 0.06, level * 0.38)];
    };
    let (primary_hue, primary_saturation, _) =
        rgb_to_hsv(primary.red / primary.weight, primary.green / primary.weight, primary.blue / primary.weight);
    let muted_saturation = (primary_saturation * 0.55).clamp(0.16, 0.38);
    let second = ranked
        .iter()
        .find(|bucket| hue_distance(bucket.hue, primary.hue) >= 35.0 && bucket.weight >= primary.weight * 0.45);
    let second_hue = second.map(|bucket| bucket.hue).unwrap_or(primary_hue + 14.0);
    let second_saturation = if second.is_some() { (muted_saturation * 0.9).min(0.32) } else { muted_saturation * 0.7 };
    vec![
        hsv_to_rgb(primary_hue, muted_saturation, 0.46),
        hsv_to_rgb(second_hue, second_saturation, if second.is_some() { 0.36 } else { 0.3 }),
        hsv_to_rgb(primary_hue, (muted_saturation * 0.6).min(0.24), 0.2),
    ]
}
