#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEAdvertising.h>

#define SERVICE_UUID "12345678-1234-1234-1234-1234567890ab"

void setup() {
  Serial.begin(115200);

  // Inicializar BLE
  BLEDevice::init("Delim_C"); // Nombre visible

  BLEServer *pServer = BLEDevice::createServer();

  // Crear advertising
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();

  // Añadir UUID de servicio directamente al advertising
  pAdvertising->addServiceUUID(SERVICE_UUID);

  // Configuración de tipo y nombre
  BLEAdvertisementData scanResponseData;
  scanResponseData.setName("Delim_C");
  pAdvertising->setScanResponseData(scanResponseData);

  // Intervalo rápido (100 ms)
  pAdvertising->setMinInterval(0x00A0);
  pAdvertising->setMaxInterval(0x00A0);

  // Potencia de transmisión alta
  BLEDevice::setPower(ESP_PWR_LVL_P9);

  // Iniciar publicidad
  pAdvertising->start();
  Serial.println("Beacon BLE genérico iniciado.");
}

void loop() {
  // No se necesita código aquí
}
