#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <ctype.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>

#define FALSE 0
#define TRUE 1

#define BLOCK_SIZE 224

#define MAX_BUFFER_SIZE (64 * 1024)

char data[MAX_BUFFER_SIZE+1];
ssize_t datalen;

uint8_t block_out[224];
uint8_t *S[16];
uint8_t found_key[16];

void load_data(FILE *stream) {
    size_t ret;

    datalen = 0;
    while ((ret = fread(data + datalen, 1, 1024, stream)))
        datalen += ret;
}

uint8_t is_base64(uint8_t b) {
    return (b == '\r' || b == '\n' || b == '+' || b == '/' || isalnum(b));
}

void print_key(const uint8_t *key) {
    int i;
    fprintf(stderr, "[!] key = ");
    for (i=0; i < 16; i++) {
        fprintf(stderr, "%2.2x", key[i]);
    }
    fprintf(stderr, "\n");
}

void decrypt_block(const uint8_t *key, uint8_t len, const uint8_t *data_in, uint8_t *data_out) {
    uint8_t b, k, r;
    uint8_t i, j;

    for (i = 0; i < len; i++) {
        k = key[i % 16];
        b = data_in[i];

        b ^= k;

        r = 0;
        for (j = 0; j < 8; j++) {
            r <<= 1;
            if (b & (1 << j))
                r |= 1;
        }

        data_out[i] = r;
    }
}

void init_S(void) {
    int i, j;
    for (i = 0; i < 16; i++) {
        S[i] = malloc(sizeof(uint8_t) * 255);
        for (j = 0; j < 256; j++) {
            S[i][j] = 1;
        }
    }
}

int need_bf(void) {
    int i, j, c;
    for (i = 0; i < 16; i++) {
        c = 0;
        for (j = 0; j < 256; j++) {
            c += S[i][j];
            if (c > 1)
                return 1;
        }
    }
    return 0;
}

void do_bf(void) {
    int i, j, k, count = 0;
    size_t remaining, current_block_size;
    uint8_t key[16];
    uint8_t tmp;
    char *block_in;

    remaining = datalen;
    while (remaining > 0)  {
        current_block_size = (remaining >= BLOCK_SIZE) ? BLOCK_SIZE : remaining;
        remaining -= current_block_size;

        for (i = 0; i < 256; i++) {
            for (j = 0; j < 16; j++) 
                key[j] = i;

            block_in = data + count * BLOCK_SIZE;
            decrypt_block(key, current_block_size, (const uint8_t*) block_in , block_out);

            for (k = 0; k < current_block_size; k++) {
                tmp = block_out[k];
                j = k % 16; /* j est l'index de l'octet de la clé */
                if (!is_base64(tmp)) {
                    /* la valeur key[k % 16] pour l'octet k % 16 n'est pas possible */
                    S[j][key[j]] = 0;
                }
            }

            if (need_bf() == FALSE)
                return;
        }
        count++;
    }
}

void decrypt_data(const uint8_t *key) {
    ssize_t remaining, current_block_size;
    int count;
    char *block_in;
    ssize_t ret;

    remaining = datalen;
    count = 0;
    while (remaining > 0) {
        current_block_size = (remaining >= BLOCK_SIZE) ? BLOCK_SIZE : remaining;
        remaining -= current_block_size;

        block_in = data + count * BLOCK_SIZE;
        decrypt_block(key, current_block_size, (const uint8_t*) block_in, block_out);
        ret = write(1, block_out, current_block_size);
        if (ret == -1) {
            perror("write");
            exit(EXIT_FAILURE);
        }

        count++;
    }

}

int main(int argc, char **argv) {
    int i, j;
    FILE *f;

    if (argc != 2) {
        printf("usage: %s data ( - for stdin)\n", argv[0]);
        exit(EXIT_FAILURE);
    }

    if (!strcmp(argv[1], "-")) {
        f = stdin;
    } else {
        f = fopen(argv[1], "r");
    }
    load_data(f);

    init_S();
    fprintf(stderr, "[*] solving part 2\n");
    do_bf();

    if (need_bf()) {
        printf("brute force failed\n");
        exit(EXIT_FAILURE);
    }

    for (i = 0; i < 16; i++) {
        for (j = 0; j < 256; j ++) {
            if (S[i][j] == 1) {
                found_key[i] = j;
            }
        }
    }
    print_key(found_key);
    decrypt_data(found_key);

    exit(EXIT_SUCCESS);
}
