Quiero desarrollar una aplicación llamada "linux-builder".

Objetivo:
Crear una herramienta que permita compilar código fuente y generar ejecutables nativos para Linux de forma sencilla, similar a un "builder".

Tecnologías:
- Lenguaje: Python 3
- Interfaz gráfica: CustomTkinter
- Compilación mediante GCC, G++, Go, Rust, PyInstaller u otras herramientas según el tipo de proyecto.
- Compatible con Ubuntu 22.04+ y otras distribuciones Linux.

Características:

1. Interfaz moderna y limpia.
2. Seleccionar un proyecto o archivo fuente.
3. Detectar automáticamente el lenguaje:
   - C
   - C++
   - Python
   - Go
   - Rust
4. Permitir configurar:
   - Nombre del ejecutable.
   - Carpeta de salida.
   - Modo Debug o Release.
   - Argumentos adicionales del compilador.
5. Mostrar el proceso de compilación en una consola integrada.
6. Mostrar errores de compilación claramente.
7. Indicar cuando la compilación fue exitosa.
8. Botón para abrir la carpeta donde se generó el ejecutable.
9. Historial de compilaciones recientes.
10. Guardar la configuración del usuario.

Arquitectura:

Organizar el proyecto utilizando una arquitectura modular.

Ejemplo:

/linux-builder
│
├── main.py
├── ui/
├── compiler/
├── detectors/
├── config/
├── utils/
├── assets/
└── output/

Crear clases independientes para:

- MainWindow
- LanguageDetector
- CompilerManager
- ConfigManager
- Logger
- OutputManager

Buenas prácticas:

- Código limpio.
- Tipado.
- Documentación.
- Manejo de excepciones.
- Fácil de mantener.
- Preparado para agregar nuevos compiladores en el futuro.

La aplicación debe verse profesional y ser rápida.

Genera el proyecto completo paso a paso, creando cada archivo por separado y explicando brevemente la función de cada uno antes de escribir su contenido.