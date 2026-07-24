
## Lo que se pidió

> "quiero crear un ejecutable aquí de acuerdo con /ruta/al/archivo.sh"

## Lo que se hizo

1. Se creó `archivo.c` con la plantilla estándar (ver `~/Desktop/terminal/como_compilar.md`):

   ```c
   #include <stdlib.h>

   int main(void) {
       return system("gnome-terminal -- bash -c \"/ruta/al/archivo.sh; echo; echo 'Presiona ENTER para cerrar...'; read\"");
   }
   ```

2. Se compiló:
   ```
   gcc -O2 -o archivo archivo.c
   ```

3. Se dieron permisos de ejecución:
   ```
   chmod +x archivo
   ```

4. Se marcó como confiable para Nautilus:
   ```
   gio set archivo "metadata::trusted" true
   ```

Resultado: `archivo` queda listo para doble clic en el Escritorio, abre una terminal y corre `archivo.sh`.

## Para volver a pedirlo

Alcanza con decir: *"créame un compilado de \<archivo\>.sh en esta carpeta"*, indicando la ruta del script a lanzar.
