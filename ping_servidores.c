#include <stdlib.h>

int main(void) {
    return system("gnome-terminal -- bash -c \"/home/servisofts/Documents/GitHub/alvaro/linux-builder/ping_servidores.sh; echo; echo 'Presiona ENTER para cerrar...'; read\"");
}
