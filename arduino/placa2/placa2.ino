#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEAdvertising.h>

#define SERVICE_UUID "12345678-1234-1234-1234-1234567890ab"

BLEAdvertising *pAdvertising;
BLEAdvertisementData advertisementData;
BLEAdvertisementData scanResponseData;

uint8_t heartbeat = 0;
unsigned long lastUpdate = 0;

void setup() {
  Serial.begin(115200);

  BLEDevice::init("Delim_A");

  pAdvertising = BLEDevice::getAdvertising();

  // Nombre visible en el scan response
  scanResponseData.setName("Delim_A");
  pAdvertising->setScanResponseData(scanResponseData);

  // Intervalo rápido (100 ms)
  pAdvertising->setMinInterval(0x00A0);
  pAdvertising->setMaxInterval(0x00A0);

  // Potencia máxima
  BLEDevice::setPower(ESP_PWR_LVL_P9);

  // Añadir UUID de servicio
  pAdvertising->addServiceUUID(SERVICE_UUID);

  // Cargar datos iniciales
  actualizarAdvertising();

  // Iniciar publicidad
  pAdvertising->start();
  Serial.println("Beacon BLE con heartbeat iniciado.");
}

void loop() {
  if (millis() - lastUpdate >= 1000) {
    lastUpdate = millis();
    heartbeat++;
    if (heartbeat > 255) heartbeat = 0;
    actualizarAdvertising();
  }
}

void actualizarAdvertising() {
  advertisementData = BLEAdvertisementData();

  // Datos manufacturer específicos (ID fabricante + heartbeat)
  uint8_t mfrData[2];
  mfrData[0] = 0x01;        // ID fabricante ficticio
  mfrData[1] = heartbeat;   // Latido

  // Convertir a String de Arduino
  String mfrString((char*)mfrData, 2);

  advertisementData.setManufacturerData(mfrString);

  pAdvertising->setAdvertisementData(advertisementData);

  Serial.printf("Heartbeat: %d\n", heartbeat);
}
