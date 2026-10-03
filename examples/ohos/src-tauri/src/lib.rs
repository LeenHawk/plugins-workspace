use std::sync::atomic::{AtomicUsize, Ordering};

static PROBE_CALLS: AtomicUsize = AtomicUsize::new(0);

#[tauri::command]
fn host_probe_echo(request: tauri::ipc::Request<'_>) -> tauri::ipc::Response {
    match request.body() {
        tauri::ipc::InvokeBody::Raw(bytes) => tauri::ipc::Response::new(bytes.clone()),
        tauri::ipc::InvokeBody::Json(_) => tauri::ipc::Response::new(Vec::<u8>::new()),
    }
}

#[tauri::command]
fn host_probe_record() {
    PROBE_CALLS.fetch_add(1, Ordering::SeqCst);
}

#[tauri::command]
fn host_probe_count() -> usize {
    PROBE_CALLS.load(Ordering::SeqCst)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            host_probe_echo,
            host_probe_record,
            host_probe_count
        ])
        .plugin(tauri_plugin_clipboard_manager::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_barcode_scanner::init())
        .run(tauri::generate_context!())
        .expect("OHOS plugin demo failed");
}
