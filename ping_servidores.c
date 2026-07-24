#include <stdlib.h>

int main(void) {
    return system("gnome-terminal -- bash -c \"/home/servisofts/Desktop/servidores/ping_servidores.sh; echo; echo 'Presiona ENTER para cerrar...'; read\"");
}
