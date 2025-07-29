#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>

// Configuración WiFi
const char* ssid = "Xiaomi_6";
const char* password = "Cuarto123";

// Configuración API
const char* apiUrl = "http://192.168.31.197:3000/api/registros";

// Configuración LED
const int wifiLedPin = 2; // GPIO2 (LED integrado en muchas placas ESP32)

// UUIDs para BLE
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

BLECharacteristic* pCharacteristic;
bool deviceConnected = false;

void registrarConexionBLE();

class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
    Serial.println("Conectado BLE");
    registrarConexionBLE();
  }

  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
    Serial.println("Desconectado BLE");

    delay(100);  // da tiempo a liberar recursos
    BLEDevice::startAdvertising();
    Serial.println("Reanudando publicidad BLE");
  }
};

void registrarConexionBLE() {
  if (WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    http.begin(apiUrl);
    http.addHeader("Content-Type", "application/json");

    StaticJsonDocument<200> doc;
    doc["id_dispositivo"] = "ESP32-URBANI";
    doc["nombre_entrada"] = "BLE conectado";

    String jsonBody;
    serializeJson(doc, jsonBody);

    int httpCode = http.POST(jsonBody);

    if (httpCode > 0) {
      Serial.print("Registrado en API. Código: ");
      Serial.println(httpCode);
    } else {
      Serial.print("Fallo en POST. Código: ");
      Serial.println(httpCode);
    }

    http.end();
  } else {
    Serial.println("WiFi no conectado");
  }
}

void connectToWiFi() {
  if(WiFi.status() == WL_CONNECTED) {
    digitalWrite(wifiLedPin, HIGH); // Enciende LED si ya está conectado
    return;
  }
  
  digitalWrite(wifiLedPin, LOW); // Apaga LED durante conexión
  WiFi.disconnect();
  delay(100);
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  WiFi.persistent(true);
  
  Serial.print("Conectando WiFi a ");
  Serial.println(ssid);
  
  WiFi.begin(ssid, password);
  
  unsigned long startAttemptTime = millis();
  
  while(WiFi.status() != WL_CONNECTED && millis() - startAttemptTime < 10000) {
    delay(500);
    Serial.print(".");
    digitalWrite(wifiLedPin, !digitalRead(wifiLedPin)); // Parpadeo durante conexión
  }
  
  if(WiFi.status() != WL_CONNECTED) {
    Serial.println("\nFallo en conexión WiFi");
    digitalWrite(wifiLedPin, LOW);
    ESP.restart();
  } else {
    digitalWrite(wifiLedPin, HIGH); // Enciende LED cuando conectado
    Serial.println("\nWiFi conectado");
    Serial.print("IP: ");
    Serial.println(WiFi.localIP());
  }
}

void setup() {
  Serial.begin(115200);
  
  // Configurar pin del LED
  pinMode(wifiLedPin, OUTPUT);
  digitalWrite(wifiLedPin, LOW); // Inicia con LED apagado
  
  connectToWiFi();

  BLEDevice::init("ESP32-BLE-URBANI");
  BLEServer* pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService* pService = pServer->createService(SERVICE_UUID);

  pCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_READ |
    BLECharacteristic::PROPERTY_WRITE |
    BLECharacteristic::PROPERTY_NOTIFY
  );

  pCharacteristic->addDescriptor(new BLE2902());
  pCharacteristic->setValue("Hola");

  pService->start();
  BLEDevice::getAdvertising()->start();
  Serial.println("Esperando conexión BLE...");
}

void loop() {
  static unsigned long lastWifiCheck = 0;
  
  // Verificar estado WiFi periódicamente
  if(millis() - lastWifiCheck > 5000) {
    lastWifiCheck = millis();
    
    if(WiFi.status() != WL_CONNECTED) {
      digitalWrite(wifiLedPin, LOW); // Apaga LED si WiFi se desconecta
      Serial.println("WiFi desconectado, intentando reconectar...");
      connectToWiFi();
    } else {
      digitalWrite(wifiLedPin, HIGH); // Mantiene LED encendido si está conectado
    }
  }

  if (deviceConnected) {
    static unsigned long lastTime = 0;
    if (millis() - lastTime > 2000) {
      lastTime = millis();
      char mensaje[32];
      snprintf(mensaje, sizeof(mensaje), "Msg %lu", millis() / 1000);
      pCharacteristic->setValue(mensaje);
      pCharacteristic->notify();
      Serial.print("Notificando: ");
      Serial.println(mensaje);
    }
  }
}