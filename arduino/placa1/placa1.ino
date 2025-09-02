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
String receivedIdDispositivo = "";
String receivedNombreEntrada = "";

// Función para enviar mensaje de respuesta a través de BLE
void enviarRespuestaBLE(const String& mensaje) {
  if (deviceConnected) {
    pCharacteristic->setValue(mensaje.c_str());
    pCharacteristic->notify();
    Serial.print("Respuesta BLE enviada: ");
    Serial.println(mensaje);
  } else {
    Serial.println("Dispositivo no conectado, no se puede enviar respuesta BLE");
  }
}

// Callback para manejar escrituras en la característica BLE
class MyCharacteristicCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pCharacteristic) {
    String value = pCharacteristic->getValue().c_str();
    
    if (value.length() > 0) {
      Serial.print("Datos recibidos via BLE: ");
      Serial.println(value.c_str());
      
      // Parsear los datos recibidos (formato esperado: "id_dispositivo;nombre_entrada")
      String data = String(value.c_str());
      int separatorIndex = data.indexOf(';');
      
      if (separatorIndex != -1) {
        receivedIdDispositivo = data.substring(0, separatorIndex);
        receivedNombreEntrada = data.substring(separatorIndex + 1);
        
        Serial.print("ID Dispositivo: ");
        Serial.println(receivedIdDispositivo);
        Serial.print("Nombre Entrada: ");
        Serial.println(receivedNombreEntrada);
        
        // Enviar datos a la API solo si ambos campos están presentes
        if (receivedIdDispositivo.length() > 0 && receivedNombreEntrada.length() > 0) {
          registrarConexionBLE();
        } else {
          enviarRespuestaBLE("ERROR: Campos vacíos");
        }
      } else {
        enviarRespuestaBLE("ERROR: Formato incorrecto. Usar: id;nombre");
      }
    }
  }
};

void registrarConexionBLE() {
  if (WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    http.begin(apiUrl);
    http.addHeader("Content-Type", "application/json");

    StaticJsonDocument<200> doc;
    doc["id_dispositivo"] = receivedIdDispositivo;
    doc["nombre_entrada"] = receivedNombreEntrada;

    String jsonBody;
    serializeJson(doc, jsonBody);

    Serial.print("Enviando a API: ");
    Serial.println(jsonBody);

    int httpCode = http.POST(jsonBody);
    String responsePayload = "N/A";

    if (httpCode > 0) {
      responsePayload = http.getString();
      Serial.print("Registrado en API. Código: ");
      Serial.println(httpCode);
      Serial.print("Respuesta: ");
      Serial.println(responsePayload);
      
      // Enviar respuesta exitosa por BLE
      String mensajeExito = "SUCCESS: Código " + String(httpCode) + " - " + responsePayload;
      enviarRespuestaBLE(mensajeExito);
      
    } else {
      Serial.print("Fallo en POST. Código: ");
      Serial.println(httpCode);
      
      // Enviar error por BLE
      String mensajeError = "ERROR: Fallo HTTP - Código " + String(httpCode);
      enviarRespuestaBLE(mensajeError);
    }

    http.end();
    
    // Limpiar los datos después de enviarlos
    receivedIdDispositivo = "";
    receivedNombreEntrada = "";
    
  } else {
    Serial.println("WiFi no conectado, no se puede enviar a API");
    enviarRespuestaBLE("ERROR: WiFi desconectado");
  }
}

class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
    Serial.println("Conectado BLE");
    enviarRespuestaBLE("Conectado. Enviar: id;nombre");
  }

  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
    Serial.println("Desconectado BLE");

    delay(100);  // da tiempo a liberar recursos
    BLEDevice::startAdvertising();
    Serial.println("Reanudando publicidad BLE");
  }
};

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

  BLEDevice::init("BLE_URBANI");
  BLEServer* pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService* pService = pServer->createService(SERVICE_UUID);

  pCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_READ |
    BLECharacteristic::PROPERTY_WRITE |
    BLECharacteristic::PROPERTY_NOTIFY
  );

  // Añadir callback para manejar escrituras
  pCharacteristic->setCallbacks(new MyCharacteristicCallbacks());
  
  pCharacteristic->addDescriptor(new BLE2902());
  pCharacteristic->setValue("Listo. Enviar: id;nombre");

  pService->start();
  BLEDevice::getAdvertising()->start();
  Serial.println("Esperando conexión BLE...");
  Serial.println("Formato esperado: id_dispositivo;nombre_entrada");
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

  // Notificaciones periódicas (opcional, puedes comentar si no las necesitas)
  if (deviceConnected) {
    static unsigned long lastTime = 0;
    if (millis() - lastTime > 10000) { // Reducido a 10 segundos para menos spam
      lastTime = millis();
      char mensaje[50];
      snprintf(mensaje, sizeof(mensaje), "Dispositivo activo - %lu", millis() / 1000);
      pCharacteristic->setValue(mensaje);
      pCharacteristic->notify();
      Serial.print("Notificando: ");
      Serial.println(mensaje);
    }
  }
}