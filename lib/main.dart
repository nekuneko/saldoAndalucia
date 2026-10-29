import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:flutter/services.dart'; 

// Definición de la paleta de colores para fácil acceso
const colorJungleGreen =  Color(0xFF007136);
const colorPaleAqua    =  Color(0xFFB3E1C5);

// Definición del patrón del fondo de la tarjeta
const List<String> _cardPattern = [
  "NeKu NeKo",
  "Junta de Andalucía. Diputación provincial de Cádiz. Ayuntamiento de Cádiz. Ayuntamiento de Chiclana. Ayuntamiento de El Puerto de Santa María. Ayuntamiento de Jerez. Ayuntamiento de Puerto Real. Ayuntamiento de Rota. Ayuntamiento de San Fernando."
];
// Randomizar el patrón de la tarjeta cuando se abre la app
final int _patternIndex = Random().nextInt(_cardPattern.length); 


void main() async {
  // Habilita solo la orientación vertical
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const TransportCardReader(),
    );
  }
}

class TransportCardReader extends StatefulWidget {
  const TransportCardReader({super.key});
  
  @override
  State<TransportCardReader> createState() => _TransportCardReaderState();
}

class _TransportCardReaderState extends State<TransportCardReader> {
  String _status = "Pulse para iniciar escaneo";
  String _cardUID = "No detectado";
  String _saldoFinal = "";
  bool _isReading = false;
  bool _showUID = false;

  // 1 unidad = 0.005 euros
  double _parseSaldo(List<int> blockData) {
    int b0 = blockData[0] & 0xFF;
    int b1 = blockData[1] & 0xFF;
    int b2 = blockData[2] & 0xFF;
    int b3 = blockData[3] & 0xFF;

    // Reconstrucción del entero de 32 bits en Little Endian (Unidades extraídas)
    int unidades = (b3 << 24) | (b2 << 16) | (b1 << 8) | b0;
    
    // Retornamos el saldo calculado
    return unidades * 0.005;
  }

  Future<void> _startNfcSession() async {

    // 1. VERIFICACIÓN PREVIA (Salida temprana si no hay NFC)
    var availability = await FlutterNfcKit.nfcAvailability;
    if (availability != NFCAvailability.available) {
      setState(() {
        _status = "Active la comunicación NFC en los ajustes de su móvil";
        _isReading = false;
      });
      return; // Cortamos el flujo limpiamente
    }

    setState(() {
      _isReading = true;
      _status = "Aproxime su tarjeta monedero a la parte trasera de su móvil...";
      _cardUID = "No detectado";
      _saldoFinal = "";
    });

    try {
      // 2. Escaneo de radiofrecuencia
      NFCTag tag = await FlutterNfcKit.poll(
        timeout: const Duration(seconds: 20),
      );

      // 3. Validación de tipo de tarjeta
      if (tag.type != NFCTagType.mifare_classic) {
        throw const FormatException("La tarjeta detectada no es una MIFARE Classic estándar.");
      }

      setState(() {
        _status = "Tarjeta detectada\nAutenticando Sector 9...";
        _cardUID = tag.id.toUpperCase();
      });

      // 4. AUTENTICACIÓN CRIPTOGRÁFICA (Aquí se debe recibir la clave del sector 9) 
      // Si no se proporciona ninguna clave al compilar, usará una vacía por defecto
      const String llave = String.fromEnvironment('CLAVE_SECTOR_9', defaultValue: '');

      // Probamos la llave usando la API NATIVA de la librería
      try {
        await FlutterNfcKit.authenticateSector(9, keyA: llave); // Autenticar la clave en el sector 9 (Monedero)
      } catch (_) {
        // Si falla la llave nativa, capturamos el error específico aquí dentro
        throw const FormatException("Llave criptográfica denegada. Acceso restringido al Sector 9.");
      }
      
      setState(() { _status = "Clave aceptada\nLeyendo bloque 37..."; });

      // 5. Lectura nativa del Bloque 37 usando la API nativa de la librería
      var dataBlock37 = await FlutterNfcKit.readBlock(37); // Bloque 37 físico de la tarjeta (Sector 9, Bloque 1)

      // 6. Validar el bloque y procesar el saldo
      if (dataBlock37.length >= 4) {
        double saldo = _parseSaldo(dataBlock37);
        setState(() {
          _saldoFinal = "${saldo.toStringAsFixed(2)} €";
          _status = "Lectura completada con éxito\nPulse para volver a escanear";
        });
      } else {
        throw const FormatException("Datos insuficientes en el sector del monedero.");
      }

    } catch (e) {
      final String rawError = e.toString().toLowerCase();
      String userFriendlyMessage = "Error inesperado durante la lectura.";

      // Comprobamos primero si es una de nuestras validaciones manuales de texto (FormatException)
      if (e is FormatException) {
        userFriendlyMessage = "Error: ${e.message}";
      } 
      // Si no, procesamos los errores físicos de la antena de radiofrecuencia
      else if (rawError.contains("timeout")) {
        userFriendlyMessage = "Error: Tiempo de espera agotado. No se detectó ninguna tarjeta.";
      } else if (rawError.contains("session invalidated") || rawError.contains("transceive") || rawError.contains("lost")) {
        userFriendlyMessage = "Error: Tarjeta retirada demasiado pronto. Mantén la tarjeta fija.";
      } else if (rawError.contains("system bus") || rawError.contains("collision")) {
        userFriendlyMessage = "Error: Múltiples tarjetas detectadas. Aproxima solo la tarjeta de transporte.";
      } else {
        userFriendlyMessage = "Error: ${e.toString().replaceAll("Exception:", "").trim()}";
      }

      setState(() {
        _status = userFriendlyMessage;
        _isReading = false;
      });
    } finally {
      // Cerramos la sesión NFC de forma limpia
      await FlutterNfcKit.finish(); 
      setState(() {
        _isReading = false;
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    final isDarkMode = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDarkMode ? ThemeData.dark().scaffoldBackgroundColor : Colors.white,
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Tarjeta de saldo simulada
            GestureDetector(
              onTap: () {
                setState(() {
                  _showUID = !_showUID; // Cambia entre true y false al tocar
                });
              },
              child: Card(
                elevation: 5,
                clipBehavior: Clip.antiAlias, 
                shadowColor: isDarkMode ? Colors.white24 : Colors.black38, 
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide.none,
                ),
                child: Container(
                  color: colorPaleAqua, // Fondo general de la tarjeta
                  child: Column(
                    children: [
                      // Franja superior de la tarjeta (Estilo tarjeta de transporte)
                      Container(
                        width: double.infinity,
                        color: colorJungleGreen,
                        padding: const EdgeInsets.symmetric(vertical: 12.0),
                        child: Text(
                          _saldoFinal.isNotEmpty ? "SALDO DISPONIBLE" : "Consorcio de Transportes",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white, // Letras en blanco
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            fontStyle: _saldoFinal.isNotEmpty ? FontStyle.normal : FontStyle.italic,
                          ),
                        ),
                      ),
                      // Cuerpo de la tarjeta con el saldo y el UID
                      SizedBox(
                        width: double.infinity,
                        child: CustomPaint(
                          painter: TextPatternPainter(
                            text: _cardPattern[_patternIndex], // El texto que se repetirá
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white24 // en un color blanquecino transparente
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              children: [
                                const SizedBox(height: 10),
                                Text(
                                  _saldoFinal,
                                  style: TextStyle(
                                    fontSize: 48,
                                    fontWeight: FontWeight.bold,
                                    color: colorJungleGreen
                                  ),
                                ),
                                const SizedBox(height: 15),
                                Text(
                                  _showUID ? "UID Tarjeta: $_cardUID" : "",
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 14,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              height: 48,
              child: Text(
                _status,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.3,
                  color: _status.startsWith("Error")// (_isReading || _status.startsWith("Error")) 
                      ? Colors.orange.shade800 
                      : (isDarkMode ? Colors.white70 : colorJungleGreen),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 40),
            // Botón de escaneo personalizado
            ElevatedButton.icon(
              onPressed: _isReading ? null : _startNfcSession,
              icon: const Icon(Icons.contactless_outlined, color: Colors.white),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 16.0),
                child: Text(
                  "ESCANEAR TARJETA",
                  style: TextStyle(
                    fontSize: 18, 
                    color: Colors.white, // Letras en blanco
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorJungleGreen, // Fondo del botón verde oscuro
                disabledBackgroundColor: colorJungleGreen.withValues(alpha: 0.6), // Opacidad si está deshabilitado
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Painter para dibujar el patron del fondo de la tarjeta
class TextPatternPainter extends CustomPainter {
  final String text;
  final TextStyle style;

  TextPatternPainter({required this.text, required this.style});

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Calculamos de forma aproximada cuántos caracteres se necesitan para llenar la tarjeta.
    // Un carácter promedio a tamaño de fuente 9-10 ocupa unos 6 píxeles de ancho.
    final double caracteresPorLinea = size.width / 6;
    final double lineasAproximadas = size.height / (style.fontSize ?? 10);
    final int caracteresTotalesNecesarios = (caracteresPorLinea * lineasAproximadas).ceil();

    // 2. Multiplicamos dinámicamente la cadena.
    // Si el texto es corto, se repetirá muchas veces. Si es largo, se repetirá solo las necesarias.
    final int vecesARepetir = max(1, (caracteresTotalesNecesarios / text.length).ceil());
    final String textoMasivo = List.generate(vecesARepetir, (index) => text).join(" ");

    // 3. Configuramos el pintor fijando el ancho de la tarjeta para permitir el desborde real.
    final textPainter = TextPainter(
      text: TextSpan(
        text: textoMasivo.replaceAll('\n', ' '), // Limpiamos saltos accidentales
        style: style,
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.justify, // Mantiene el elegante justificado de lado a lado
    );

    // Forzamos a Flutter a renderizar con salto de línea al llegar al borde horizontal de la tarjeta.
    textPainter.layout(maxWidth: size.width);

    // 4. Pintamos el bloque entero. Ahora sí fluirá continuo y cubrirá toda la tarjeta.
    textPainter.paint(canvas, const Offset(0, 0));
  }

  // OPTIMIZACIÓN: Se permite que repinte solo si cambia el texto o el estilo, optimizando el uso de caché de Flutter
  @override
  bool shouldRepaint(covariant TextPatternPainter oldDelegate) {
    return oldDelegate.text != text || oldDelegate.style != style;
  }
}




