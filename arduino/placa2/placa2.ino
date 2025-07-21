#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// UUIDs para el servicio y la característica
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

BLECharacteristic *pCharacteristic;
bool deviceConnected = false;

class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
    Serial.println("Dispositivo conectado");
  }

  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
    Serial.println("Dispositivo desconectado");
    // 🔁 Reiniciar la publicidad para ser visible otra vez
    BLEDevice::startAdvertising();
    Serial.println("Reiniciando publicidad BLE...");
  }
};

void setup() {
  Serial.begin(115200);

  // Inicializa el dispositivo BLE
  BLEDevice::init("ESP32-BLE-URBANI-2"); // Nombre del dispositivo
  BLEServer *pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  // Crea un servicio BLE
  BLEService *pService = pServer->createService(SERVICE_UUID);

  // Crea una característica BLE
  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      BLECharacteristic::PROPERTY_READ |
                      BLECharacteristic::PROPERTY_WRITE |
                      BLECharacteristic::PROPERTY_NOTIFY
                    );

  // Agrega descriptor para notificaciones
  pCharacteristic->addDescriptor(new BLE2902());

  // Establece valor inicial
  pCharacteristic->setValue("Hola desde ESP32");

  // Inicia el servicio
  pService->start();

  // Empieza la publicidad BLE
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->start();
  Serial.println("Esperando conexión por BLE...");
}

void loop() {
  if (deviceConnected) {
    // Enviar una notificación cada 2 segundos
    static unsigned long lastTime = 0;
    if (millis() - lastTime > 2000) {
      lastTime = millis();
      String mensaje = "Mensaje " + String(millis() / 1000);
      pCharacteristic->setValue(mensaje.c_str());
      pCharacteristic->notify(); // Envía el valor al cliente
      Serial.println("Notificando: " + mensaje);
    }
  }
}