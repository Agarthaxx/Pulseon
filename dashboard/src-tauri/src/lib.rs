mod data;

use chrono::Local;

#[tauri::command]
fn day_view(date: Option<String>) -> Result<data::DayView, String> {
    let date = date.unwrap_or_else(|| Local::now().format("%Y-%m-%d").to_string());
    data::day_view(&date)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![day_view])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
