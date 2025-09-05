#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>

// Configuración WiFi
const char* ssid = "Steren COM-852";
const char* password = "12345678";

// Configuración API - DEFINIR ESTOS VALORES SEGÚN TU CASETA
const int TOLL_ID = 2;  // ID de la caseta (debe coincidir con la BD)
const String ID_DISPOSITIVO = "BLE_CASETA2"; // ID del dispositivo (debe coincidir con la BD)

// URLs de la API
const String API_BASE = "http://192.168.31.197:3000";
const String TARIFFS_URL = API_BASE + "/api/tariffs";
const String REGISTROS_URL = API_BASE + "/api/registros/registrar-ingreso";

// Configuración LED
const int wifiLedPin = 2; // GPIO2 (LED integrado en muchas placas ESP32)

// UUIDs para BLE
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

BLECharacteristic* pCharacteristic;
bool deviceConnected = false;
String receivedVehicleType = "";
String receivedIdUsuario = "";

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

// Función para obtener tarifa desde la API
String obtenerTarifa(const String& vehicleType) {
  if (WiFi.status() != WL_CONNECTED) {
    return "ERROR: WiFi desconectado";
  }

  HTTPClient http;
  String url = TARIFFS_URL + "?toll_id=" + String(TOLL_ID) + "&vehicle_type=" + vehicleType;
  http.begin(url);
  
  Serial.print("Consultando tarifa: ");
  Serial.println(url);

  int httpCode = http.GET();
  String response = "N/A";

  if (httpCode == 200) {
    response = http.getString();
    Serial.print("Respuesta tarifa: ");
    Serial.println(response);
    
    // Parsear JSON para extraer la tarifa
    StaticJsonDocument<200> doc;
    DeserializationError error = deserializeJson(doc, response);
    
    if (!error && doc["ok"] == true && doc["data"].containsKey("tariff")) {
      float tarifa = doc["data"]["tariff"];
      response = "TARIFA:" + String(tarifa, 2);
    } else {
      response = "ERROR: No se pudo obtener tarifa";
    }
  } else {
    Serial.print("Error en GET tarifa. Código: ");
    Serial.println(httpCode);
    response = "ERROR: HTTP " + String(httpCode);
  }

  http.end();
  return response;
}

// Función para registrar ingreso BLE
String registrarIngresoBLE(const String& idUsuario, const String& vehicleType) {
  if (WiFi.status() != WL_CONNECTED) {
    return "ERROR: WiFi desconectado";
  }

  HTTPClient http;
  http.begin(REGISTROS_URL);
  http.addHeader("Content-Type", "application/json");

  // Crear JSON para el registro
  StaticJsonDocument<200> doc;
  doc["id_dispositivo"] = ID_DISPOSITIVO;
  doc["id_usuario"] = idUsuario;
  doc["vehicle_type"] = vehicleType;
  doc["nombre_entrada"] = "Entrada BLE";

  String jsonBody;
  serializeJson(doc, jsonBody);

  Serial.print("Enviando registro a API: ");
  Serial.println(jsonBody);

  int httpCode = http.POST(jsonBody);
  String response = "N/A";

  if (httpCode == 201 || httpCode == 200) {
    response = http.getString();
    Serial.print("Registro exitoso. Código: ");
    Serial.println(httpCode);
  } else {
    Serial.print("Error en registro. Código: ");
    Serial.println(httpCode);
    response = "ERROR: HTTP " + String(httpCode);
  }

  http.end();
  return response;
}

// Callback para manejar escrituras en la característica BLE
class MyCharacteristicCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pCharacteristic) {
    String value = pCharacteristic->getValue().c_str();
    
    if (value.length() > 0) {
      Serial.print("Datos recibidos via BLE: ");
      Serial.println(value.c_str());
      
      // Parsear los datos recibidos (formato: "id_usuario;vehicle_type")
      String data = String(value.c_str());
      int separatorIndex = data.indexOf(';');
      
      if (separatorIndex != -1) {
        receivedIdUsuario = data.substring(0, separatorIndex);
        receivedVehicleType = data.substring(separatorIndex + 1);
        
        Serial.print("ID Usuario: ");
        Serial.println(receivedIdUsuario);
        Serial.print("Tipo Vehículo: ");
        Serial.println(receivedVehicleType);
        
        // Validar campos
        if (receivedIdUsuario.length() > 0 && receivedVehicleType.length() > 0) {
          // 1. Primero obtener la tarifa
          enviarRespuestaBLE("Consultando tarifa...");
          String respuestaTarifa = obtenerTarifa(receivedVehicleType);
          enviarRespuestaBLE(respuestaTarifa);
          
          delay(1000); // Pequeña pausa
          
          // 2. Luego registrar el ingreso
          enviarRespuestaBLE("Registrando ingreso...");
          String respuestaRegistro = registrarIngresoBLE(receivedIdUsuario, receivedVehicleType);
          enviarRespuestaBLE(respuestaRegistro);
          
        } else {
          enviarRespuestaBLE("ERROR: Campos vacíos");
        }
      } else {
        enviarRespuestaBLE("ERROR: Formato incorrecto. Usar: id_usuario;vehicle_type");
      }
      
      // Limpiar los datos después de procesarlos
      receivedIdUsuario = "";
      receivedVehicleType = "";
    }
  }
};

class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
    Serial.println("Conectado BLE");
    enviarRespuestaBLE("Conectado. Enviar: id_usuario;tipo_vehiculo");
  }

  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
    Serial.println("Desconectado BLE");
    delay(100);
    BLEDevice::startAdvertising();
    Serial.println("Reanudando publicidad BLE");
  }
};

void connectToWiFi() {
  if(WiFi.status() == WL_CONNECTED) {
    digitalWrite(wifiLedPin, HIGH);
    return;
  }
  
  digitalWrite(wifiLedPin, LOW);
  WiFi.disconnect();
  delay(100);
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  WiFi.persistent(true);
  
  Serial.print("Conectando WiFi a ");
  Serial.println(ssid);
  
  WiFi.begin(ssid, password);
  
  unsigned long startAttemptTime = millis();
  
  while(WiFi.status() != WL_CONNECTED && millis() - startAttemptTime < 15000) {
    delay(500);
    Serial.print(".");
    digitalWrite(wifiLedPin, !digitalRead(wifiLedPin));
  }
  
  if(WiFi.status() != WL_CONNECTED) {
    Serial.println("\nFallo en conexión WiFi");
    digitalWrite(wifiLedPin, LOW);
  } else {
    digitalWrite(wifiLedPin, HIGH);
    Serial.println("\nWiFi conectado");
    Serial.print("IP: ");
    Serial.println(WiFi.localIP());
  }
}

void setup() {
  Serial.begin(115200);
  
  // Configurar pin del LED
  pinMode(wifiLedPin, OUTPUT);
  digitalWrite(wifiLedPin, LOW);
  
  // Mostrar configuración
  Serial.println("=== CONFIGURACIÓN ESP32 ===");
  Serial.print("Toll ID: ");
  Serial.println(TOLL_ID);
  Serial.print("ID Dispositivo: ");
  Serial.println(ID_DISPOSITIVO);
  Serial.print("API Base: ");
  Serial.println(API_BASE);
  
  connectToWiFi();

  // Inicializar BLE
  BLEDevice::init("BLE_B");
  BLEServer* pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService* pService = pServer->createService(SERVICE_UUID);

  pCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_READ |
    BLECharacteristic::PROPERTY_WRITE |
    BLECharacteristic::PROPERTY_NOTIFY
  );

  pCharacteristic->setCallbacks(new MyCharacteristicCallbacks());
  pCharacteristic->addDescriptor(new BLE2902());
  pCharacteristic->setValue("Listo. Enviar: id_usuario;tipo_vehiculo");

  pService->start();
  BLEDevice::getAdvertising()->start();
  
  Serial.println("=== BLE INICIADO ===");
  Serial.println("Esperando conexión BLE...");
  Serial.println("Formato esperado: id_usuario;vehicle_type");
  Serial.println("Ejemplo: USER_123;CARRO");
}

void loop() {
  static unsigned long lastWifiCheck = 0;
  
  // Verificar estado WiFi periódicamente
  if(millis() - lastWifiCheck > 10000) {
    lastWifiCheck = millis();
    
    if(WiFi.status() != WL_CONNECTED) {
      digitalWrite(wifiLedPin, LOW);
      Serial.println("WiFi desconectado, intentando reconectar...");
      connectToWiFi();
    } else {
      digitalWrite(wifiLedPin, HIGH);
    }
  }

  // Notificación de estado periódica
  if (deviceConnected) {
    static unsigned long lastTime = 0;
    if (millis() - lastTime > 30000) {
      lastTime = millis();
      String statusMsg = "Caseta " + String(TOLL_ID) + " - Online";
      pCharacteristic->setValue(statusMsg.c_str());
      pCharacteristic->notify();
      Serial.println("Notificación de estado enviada");
    }
  }
}