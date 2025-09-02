#include <WiFi.h>
#include <WebServer.h>
#include <ArduinoJson.h>

const char* ssid = "Xiaomi_6";
const char* password = "Cuarto123";

WebServer server(80);
const int ledPin = 2; // Ajusta el pin del LED

// Variables para el control del estado de conexión y timing
unsigned long previousMillis = 0;
const long interval = 10000; // Intervalo para mostrar IP (10 segundos)
bool wifiConnected = false;

void handleActivateLed() {
  if (server.method() == HTTP_POST) {
    String body = server.arg("plain");
    
    // Parsear JSON
    DynamicJsonDocument doc(1024);
    DeserializationError error = deserializeJson(doc, body);
    
    if (error) {
      server.send(400, "application/json", "{\"error\":\"JSON inválido\"}");
      return;
    }
    
    // Obtener parámetros
    int duration = doc["duration"] | 3000; // Default 3 segundos
    
    // Encender LED
    digitalWrite(ledPin, HIGH);
    Serial.println("LED activado por " + String(duration) + "ms");
    
    // Responder inmediatamente
    server.send(200, "application/json", "{\"status\":\"LED activado\"}");
    
    // Apagar LED después del tiempo especificado (no bloqueante)
    unsigned long startTime = millis();
    while (millis() - startTime < duration) {
      // Esperar sin bloquear el servidor
      server.handleClient();
      delay(100);
    }
    
    digitalWrite(ledPin, LOW);
    Serial.println("LED desactivado");
    
  } else {
    server.send(405, "application/json", "{\"error\":\"Método no permitido\"}");
  }
}

void checkWiFiConnection() {
  if (WiFi.status() != WL_CONNECTED) {
    if (wifiConnected) {
      Serial.println("Conexión WiFi perdida");
      wifiConnected = false;
    }
    
    // Parpadear LED cuando no hay conexión (500ms encendido, 500ms apagado)
    unsigned long currentMillis = millis();
    if (currentMillis - previousMillis >= 500) {
      previousMillis = currentMillis;
      digitalWrite(ledPin, !digitalRead(ledPin)); // Alternar estado del LED
    }
    
    // Intentar reconectar cada 10 segundos
    static unsigned long lastReconnectAttempt = 0;
    if (currentMillis - lastReconnectAttempt >= 10000) {
      lastReconnectAttempt = currentMillis;
      Serial.println("Intentando reconectar a WiFi...");
      WiFi.disconnect();
      WiFi.begin(ssid, password);
    }
    
  } else {
    if (!wifiConnected) {
      wifiConnected = true;
      digitalWrite(ledPin, LOW); // Asegurar que el LED esté apagado cuando se conecte
      Serial.println("\nConectado a WiFi! IP: " + WiFi.localIP().toString());
    }
    
    // Mostrar IP periódicamente
    unsigned long currentMillis = millis();
    if (currentMillis - previousMillis >= interval) {
      previousMillis = currentMillis;
      Serial.println("IP actual: " + WiFi.localIP().toString() + 
                    " - Señal RSSI: " + String(WiFi.RSSI()) + " dBm");
    }
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(ledPin, OUTPUT);
  digitalWrite(ledPin, LOW);
  
  Serial.println("Iniciando conexión WiFi...");
  Serial.println("SSID: " + String(ssid));
  
  // Conectar WiFi
  WiFi.begin(ssid, password);
  
  // Configurar tiempo máximo de conexión
  unsigned long startTime = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - startTime < 15000) {
    delay(500);
    Serial.print(".");
    digitalWrite(ledPin, !digitalRead(ledPin)); // Parpadear durante conexión
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    wifiConnected = true;
    digitalWrite(ledPin, LOW);
    Serial.println("\nConectado! IP: " + WiFi.localIP().toString());
  } else {
    Serial.println("\nError: No se pudo conectar al WiFi");
    Serial.println("El LED parpadeará indicando falta de conexión");
  }
  
  // Configurar rutas del servidor
  server.on("/activate-led", HTTP_POST, handleActivateLed);
  
  server.begin();
  Serial.println("Servidor HTTP iniciado");
  Serial.println("Mostrando IP cada 10 segundos...");
}

void loop() {
  checkWiFiConnection(); // Verificar estado de la conexión
  server.handleClient(); // Manejar peticiones del servidor
}