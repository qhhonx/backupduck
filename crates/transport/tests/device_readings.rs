use backupduck_store::Receiver;
use backupduck_transport::{observation_time_ms, shared_router_with_readings, DeviceReadings};
use std::sync::{Arc, Mutex};

#[tokio::test]
async fn readings_require_pairing_and_expire_temperature_without_inventing_free_space() {
    let root = std::env::temp_dir().join(format!("duck-readings-{}", std::process::id()));
    let receiver = Arc::new(Mutex::new(Receiver::open(&root, 1024).unwrap()));
    let readings = Arc::new(Mutex::new(DeviceReadings::default()));
    let token = "a".repeat(64);
    let router = shared_router_with_readings(receiver, &token, None, readings.clone()).unwrap();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}/v2/device-status", listener.local_addr().unwrap());
    let server = tokio::spawn(async move { axum::serve(listener, router).await.unwrap() });
    let http = reqwest::Client::new();
    assert_eq!(http.get(&url).send().await.unwrap().status(), 401);
    let request = || http.get(&url).bearer_auth(&token);
    let empty: DeviceReadings = request().send().await.unwrap().json().await.unwrap();
    assert!(empty.temperature_deci_celsius.is_none());
    assert!(
        empty.free_bytes.unwrap() > 1024,
        "physical free space is not the configured cache budget"
    );
    *readings.lock().unwrap() = DeviceReadings {
        temperature_deci_celsius: Some(327),
        temperature_observed_at_ms: Some(observation_time_ms()),
        free_bytes: None,
    };
    let fresh: DeviceReadings = request().send().await.unwrap().json().await.unwrap();
    assert_eq!(fresh.temperature_deci_celsius, Some(327));
    readings.lock().unwrap().temperature_observed_at_ms = Some(1);
    let stale: DeviceReadings = request().send().await.unwrap().json().await.unwrap();
    assert!(stale.temperature_deci_celsius.is_none());
    assert!(stale.temperature_observed_at_ms.is_none());
    server.abort();
    std::fs::remove_dir_all(root).unwrap();
}
