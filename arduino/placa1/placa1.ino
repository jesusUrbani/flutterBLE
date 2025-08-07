#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEBeacon.h>
#include <BLEAdvertising.h>

void setup() {
  Serial.begin(115200);

  BLEDevice::init("Delim_A");

  BLEBeacon oBeacon = BLEBeacon();
  oBeacon.setManufacturerId(0x004C);  // Apple ID
  oBeacon.setProximityUUID(BLEUUID("12345678-1234-1234-1234-1234567890ab"));
  oBeacon.setMajor(100);
  oBeacon.setMinor(1);
  oBeacon.setSignalPower(-59);

  BLEAdvertisementData oAdvertisementData;
  BLEAdvertisementData oScanResponseData;

  // Usa un objeto String (Arduino) para evitar problemas con std::string
  String serviceData = "";
  serviceData += (char)26;
  serviceData += (char)0xFF;
  serviceData += oBeacon.getData();  // ✅ Esto ya es tipo String, y funciona bien

  oAdvertisementData.setFlags(0x04); // Discoverable
  oAdvertisementData.addData(serviceData);  // ✅ addData espera String

  oScanResponseData.setName("Delim_A");

  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->setAdvertisementData(oAdvertisementData);
  pAdvertising->setScanResponseData(oScanResponseData);
  pAdvertising->setAdvertisementType(ADV_TYPE_IND); // Conectable
  pAdvertising->start();

  Serial.println("iBeacon 'Delim_A' iniciado.");
}

void loop() {}
