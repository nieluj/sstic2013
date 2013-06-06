#define _GNU_SOURCE
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <ctype.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <omp.h>

#include "md5.h"

#ifndef MD5_DIGEST_LENGTH
#define MD5_DIGEST_LENGTH 16
#endif

#define OMP_THREAD_LIMIT 32

#define DATA_COUNT 77
#define DATA_LEN   32

#define DATA_BUFFER_SIZE (64 * 1024)
#define EOS_MARK "cafebabe"

char atad[DATA_BUFFER_SIZE+1];

/* store pointers to I1, I2, I3, I4 */
uint8_t *I[4];
size_t I_size[4];

uint32_t I1[DATA_COUNT][DATA_LEN];
uint8_t *target_md5[6];

struct bf_ctx {
    uint32_t **data;
    uint8_t a;
    uint8_t b;
};

static uint8_t ascii2byte(uint8_t *val) {
    uint8_t temp = *val;

    if(temp > 0x60) temp -= 39;  /* convert chars a-f */
    temp -= 48;  /* convert chars 0-9 */
    temp *= 16;

    temp += *(val+1);
    if(*(val+1) > 0x60) temp -= 39;  /* convert chars a-f */
    temp -= 48;  /* convert chars 0-9 */

    return temp;
}

struct bf_ctx *new_bf_ctx(void) {
    int i;
    struct bf_ctx *ctx;

    ctx = malloc(sizeof(struct bf_ctx));

    ctx->data = (uint32_t **) malloc(sizeof(uint32_t *) * DATA_COUNT);
    for (i = 0; i < DATA_COUNT; i++) {
        ctx->data[i] = malloc(sizeof(uint32_t) * DATA_LEN);
    }
    ctx->a = 0; ctx->b = 0;

    return ctx;
}

void free_bf_ctx(struct bf_ctx *ctx) {
    int i;

    if (!ctx)
        return;

    if (ctx->data) {
        for (i = 0; i < DATA_COUNT; i++)
            if (ctx->data[i])
                free(ctx->data[i]);
    }
    free(ctx);
}

void copy_bf_ctx(struct bf_ctx *dest, struct bf_ctx *src) {
    int i;

    for (i = 0; i < DATA_COUNT; i++) {
        memcpy(dest->data[i], src->data[i], sizeof(uint32_t) * DATA_LEN);
    }
    dest->a = src->a;
    dest->b = src->b;
}

void load_data(FILE *stream) {
    int i = 0, j;
    char *prev_token, *token;
    size_t count;
    uint8_t *p;
    uint32_t t;

    if (fgets(atad, DATA_BUFFER_SIZE, stream) == NULL) {
        fprintf(stderr, "error during fgets\n");
        exit(EXIT_FAILURE);
    }

    prev_token = strtok(atad, " ");
    while ((token = strtok(NULL, " "))) {
        if (!strcmp(token, EOS_MARK)) {
            count = strlen(prev_token) / 2;
            I[i] = malloc(sizeof(uint8_t) * count);
            I_size[i] = count;
            for (j = 0; j < count; j++) {
                I[i][j] = ascii2byte( (uint8_t *) prev_token + 2 * j );
            }
            i++;
        }
        prev_token = token;
    }

    /* Convert I1 data to uint32_t */
    for (i = 0; i < DATA_COUNT; i++) {
        for (j = 0; j < DATA_LEN; j++) {
            p = I[0] + (DATA_LEN * sizeof(uint32_t)) * i + j * sizeof(uint32_t);
            t = (*p) | (*(p+1) << 8) | (*(p+2) << 16) | (*(p+3) << 24);
            I1[i][j] = t;
        }
    }

    /* Set the pointer to each MD5 target value */
    for (i = 0; i < 6; i++) {
        target_md5[i] = I[2] + i * MD5_DIGEST_LENGTH;
    }
}

int decrypt_main(uint8_t b0, uint8_t b1, const uint32_t *data, size_t data_len, uint32_t *tmp) {
    uint32_t k;
    int i;
    void *p;

    k = b0 | b1 << 8 | b0 << 16 | b1 << 24;

    for (i = 0; i < data_len; i++) {
        k = k ^ data[i];
        tmp[i] = k;
    }

    p = memmem(tmp, data_len * sizeof(uint32_t), "roll", 4);

    return (p != NULL);
}

int bf_main_I(int idx, uint8_t *key) {
    int b0, b1;
    uint8_t *p;
    uint32_t *tmp, *data;
    size_t count;
    int i, ret;

    count = I_size[idx] / 4;
    data = malloc(sizeof(uint32_t) * count);
    tmp = malloc(sizeof(uint32_t) * count);

    for (i = 0; i < count; i++) {
        p = I[idx] + i * sizeof(uint32_t);
        data[i] = (*p) | (*(p+1) << 8) | (*(p+2) << 16) | (*(p+3) << 24);
    }

    for (b0 = 0; b0 < 256; b0++) {
        for (b1 = 0; b1 < 256; b1++) {
            ret = decrypt_main(b0, b1, data, count, tmp);
            if (ret != 0) {
                key[0] = b0;
                key[1] = b1;
                goto cleanup;
            }
        }
    }

cleanup:
    free(data); free(tmp);
    return ret;
}

void bf_main(uint8_t *key) {
    int ret;

    ret = bf_main_I(1, key + 2);
    if (ret == 0) {
        fprintf(stderr, "cannot find key for I2\n");
        exit(EXIT_FAILURE);
    }

    ret = bf_main_I(3, key);
    if (ret == 0) {
        fprintf(stderr, "cannot find key for I4\n");
        exit(EXIT_FAILURE);
    }
}

static inline uint32_t lfsr(uint32_t v) {
    uint8_t bit;
    bit = ( (v >> 0) ^ (v >> 2) ^ (v >> 3) ^ (v >> 7) ) & 1;
    return (v >> 1) | (bit << 31);
}

static inline int cmp(uint32_t t) {
    if (t < 0x55555555)
        return 1;
    else {
        if (t < 0xaaaaaaaa)
            return -1;
        else
            return 0;
    }
}

void decrypt_I4(struct bf_ctx *ctx, uint8_t *key, uint8_t *md5sum) {
    int i;
    uint32_t t, tmp;
    MD5_CTX md5_ctx;
    uint32_t **data;
    uint8_t a, b, old_a, old_b;

    t = key[0] << 24 | key[1] << 16 | key[2] << 8 | key[3];

    data = ctx->data;
    a = ctx->a;
    b = ctx->b;

    for (i = 0; i < 10240; i++) {
        old_a = a;
        old_b = b;

        t = lfsr(t);
        a = (a + cmp(t) + DATA_COUNT) % DATA_COUNT;

        t = lfsr(t);
        b = (b + cmp(t) + DATA_LEN) % DATA_LEN;

        t = lfsr(t);

        /* Swapping data[c][d] and data[a][b] */
        tmp = data[a][b];
        data[a][b] = data[old_a][old_b];

        data[old_a][old_b] = tmp ^ htonl(t);
    }

    ctx->a = a; ctx->b = b;

    MD5_Init(&md5_ctx);
    for (i = 0; i < DATA_COUNT; i++) {
        MD5_Update(&md5_ctx, ctx->data[i], sizeof(uint32_t) * DATA_LEN);
    }
    MD5_Final(md5sum, &md5_ctx);
}

void bf_I4(uint8_t *key) {
#ifdef HOLLYWOOD
    int l, hcount = 0;
    uint8_t hchars[4] = { '-', '\\', '|', '/' };
#endif
    int i, j, keyfound;
    struct bf_ctx *ref_ctx;
    struct bf_ctx **threads_ctx;
    uint8_t *current_key;

    ref_ctx = new_bf_ctx();
    for (i = 0; i < DATA_COUNT; i++) {
        memcpy(ref_ctx->data[i], I1[i], sizeof(uint32_t) * DATA_LEN);
    }

    threads_ctx = malloc(OMP_THREAD_LIMIT * sizeof(struct bf_ctx *));
    for (i = 0; i < OMP_THREAD_LIMIT; i++) {
        threads_ctx[i] = new_bf_ctx();
    }

#ifdef HOLLYWOOD
    fprintf(stderr, "[+] hollywood mode engaged\n");
#endif

#pragma omp parallel
    {
#pragma omp barrier
        if (omp_get_thread_num() == 0) {
            fprintf(stderr, "[+] starting %d threads\n", omp_get_num_threads());
        }
    }

    for (i = 0; i < 6; i++) {
        keyfound = 0;
        current_key = key + 2 + 2 * i;

#pragma omp parallel for
        for (j = 0; j < 256; j++) {
            int k, thread_id;
            struct bf_ctx *tmp_ctx;
            uint8_t tmpkey[4];
            uint8_t md5sum[MD5_DIGEST_LENGTH];

            if (keyfound == 1) {
                j = 256;
                continue;
            }

            memcpy(tmpkey, current_key, 2);
            tmpkey[2] = j;

            thread_id = omp_get_thread_num();
            tmp_ctx = threads_ctx[thread_id];

            for (k = 0; k < 256; k++) {
                tmpkey[3] = k;

#ifdef HOLLYWOOD
                if (thread_id == 0 && k == 0) {
                    fprintf(stderr, "\r[%c] key = ", hchars[hcount++ % 4]);
                    for (l = 0; l < 16; l++)
                        fprintf(stderr, "%2.2x", key[l]);
                    fflush(stderr);
                }
#endif

                copy_bf_ctx(tmp_ctx, ref_ctx);
                decrypt_I4(tmp_ctx, tmpkey, md5sum);

                if (!memcmp(md5sum, target_md5[i], MD5_DIGEST_LENGTH)) {
#pragma omp critical
                    {
                        keyfound = 1;
                        copy_bf_ctx(ref_ctx, tmp_ctx);
                        memcpy(current_key, tmpkey, 4);
                    }
                }
            }
        }
        if (keyfound == 0) {
            fprintf(stderr, "key not found!\n");
            exit(0);
        } 
    }
    fprintf(stderr, "\r[!] key = ");
    for (i = 0; i < 16; i++) {
        fprintf(stderr, "%2.2x", key[i]);
    }
    fprintf(stderr, "\n");


    for (i = 0; i < DATA_COUNT; i++) {
        fwrite(ref_ctx->data[i], sizeof(uint32_t) * DATA_LEN, 1, stdout);
    }

    free_bf_ctx(ref_ctx);
    for (i = 0; i < OMP_THREAD_LIMIT; i++)
        free_bf_ctx(threads_ctx[i]);
}

int main(int argc, char **argv) {
    FILE *f;
    uint8_t key[16];

    if (argc != 2) {
        fprintf(stderr, "usage: %s input (- for stdin)\n", argv[0]);
        exit(EXIT_FAILURE);
    }

    if (!strcmp(argv[1], "-")) {
        f = stdin;
    } else {
        f = fopen(argv[1], "r");
    }
    load_data(f);

    fprintf(stderr, "[*] solving part 3\n");
    memset(key, 0, 16);
    bf_main(key);
    bf_I4(key);

    exit(EXIT_SUCCESS);}
