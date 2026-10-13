use std::collections::HashMap;
use std::hash::Hash;

pub fn ratio<T: Eq + Hash>(a: &[T], b: &[T]) -> f64 {
    let total = a.len() + b.len();
    if total == 0 {
        return 1.0;
    }
    2.0 * matching_count(a, b) as f64 / total as f64
}

pub fn ratio_str(a: &str, b: &str) -> f64 {
    let left: Vec<char> = a.chars().collect();
    let right: Vec<char> = b.chars().collect();
    ratio(&left, &right)
}

pub fn matching_count<T: Eq + Hash>(a: &[T], b: &[T]) -> usize {
    if a.is_empty() || b.is_empty() {
        return 0;
    }
    let mut positions: HashMap<&T, Vec<usize>> = HashMap::new();
    for (index, element) in b.iter().enumerate() {
        positions.entry(element).or_default().push(index);
    }
    let mut previous = vec![0usize; b.len() + 1];
    let mut current = vec![0usize; b.len() + 1];
    let mut previous_touched: Vec<usize> = Vec::new();
    let mut current_touched: Vec<usize> = Vec::new();
    let mut stack: Vec<(usize, usize, usize, usize)> = vec![(0, a.len(), 0, b.len())];
    let mut total = 0usize;
    while let Some((alo, ahi, blo, bhi)) = stack.pop() {
        let mut best_i = alo;
        let mut best_j = blo;
        let mut best_size = 0usize;
        for i in alo..ahi {
            current_touched.clear();
            if let Some(hits) = positions.get(&a[i]) {
                for &j in hits {
                    if j < blo {
                        continue;
                    }
                    if j >= bhi {
                        break;
                    }
                    let length = previous[j] + 1;
                    current[j + 1] = length;
                    current_touched.push(j + 1);
                    if length > best_size {
                        best_i = i + 1 - length;
                        best_j = j + 1 - length;
                        best_size = length;
                    }
                }
            }
            for &slot in &previous_touched {
                previous[slot] = 0;
            }
            std::mem::swap(&mut previous, &mut current);
            std::mem::swap(&mut previous_touched, &mut current_touched);
        }
        for &slot in &previous_touched {
            previous[slot] = 0;
        }
        previous_touched.clear();
        current_touched.clear();
        if best_size > 0 {
            total += best_size;
            if alo < best_i && blo < best_j {
                stack.push((alo, best_i, blo, best_j));
            }
            if best_i + best_size < ahi && best_j + best_size < bhi {
                stack.push((best_i + best_size, ahi, best_j + best_size, bhi));
            }
        }
    }
    total
}
