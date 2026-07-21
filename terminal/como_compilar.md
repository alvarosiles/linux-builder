# Cómo crear un ejecutable compilado (Ubuntu)

Guía para convertir cualquier script (`.sh`) en un ejecutable compilado que corra con doble clic desde Nautilus, sin las advertencias de "¿Ejecutar o Mostrar?" que dan los `.sh`.

## Pasos

1. Crear un archivo `nombre.c` con este contenido base, cambiando la ruta del script:

   ```c
   #include <stdlib.h>

   int main(void) {
       return system("gnome-terminal -- bash -c \"/ruta/al/script.sh; echo; echo 'Presiona ENTER para cerrar...'; read\"");
   }
   ```

   - Reemplazar `/ruta/al/script.sh` por la ruta absoluta del script que se quiera lanzar.
   - Si el resultado no necesita quedar visible, se puede quitar la parte de `echo ...; read` y dejar solo `system("/ruta/al/script.sh")`.
   - Para mostrar un mensaje/popup en vez de abrir terminal, se puede usar `zenity` en lugar de `gnome-terminal`, ej: `system("zenity --info --title=\"Titulo\" --text=\"Mensaje\"")`.

2. Compilar:
   ```
   gcc -O2 -o nombre nombre.c
   ```

3. Dar permisos de ejecución:
   ```
   chmod +x nombre
   ```

4. Marcarlo como confiable para Nautilus (evita el aviso la primera vez):
   ```
   gio set nombre "metadata::trusted" true
   ```

Con esto, el archivo `nombre` (sin extensión) queda listo para doble clic en el Escritorio.

## Ejemplos ya hechos en esta carpeta

- `saludos.c` → `saludos`: abre terminal, imprime "Hola mundo", queda abierta hasta ENTER.
- `restart_servidores.c` → `restart_servidores`: abre terminal y corre `scripts/restart_servidores.sh`, queda abierta hasta ENTER.

## Para pedir uno nuevo

Solo hace falta decir: *"créame un compilado de \<archivo\>.sh en esta carpeta"*, indicando la ruta del script a lanzar.
