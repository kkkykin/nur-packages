/* SPDX-License-Identifier: MIT */
#define _POSIX_C_SOURCE 200809L
#define _FILE_OFFSET_BITS 64
#include <dico.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <limits.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <unicase.h>
#include <unistr.h>
#include <zlib.h>

struct buffer { unsigned char *data; size_t size, capacity; };
struct entry { char *word; uint64_t offset; uint32_t size; };
struct headword { char *word, *folded; size_t entry; };
struct database {
    char *name, *base, *metadata, *info, *bookname, *sequence;
    unsigned char *index, *synonyms, *data;
    size_t data_size, entry_count, headword_count;
    struct entry *entries;
    struct headword *headwords;
    int fd;
    gzFile compressed;
};
struct result {
    struct database *db;
    size_t *items, count, capacity, comparisons;
    bool definitions;
};

#include "html_entities.h"

static int append(struct buffer *b, const void *data, size_t size)
{
    if (size > SIZE_MAX - b->size - 1) { errno = ENOMEM; return -1; }
    size_t needed = b->size + size + 1;
    if (needed > b->capacity) {
        size_t capacity = b->capacity ? b->capacity : 4096;
        while (capacity < needed) {
            if (capacity > SIZE_MAX / 2) { capacity = needed; break; }
            capacity *= 2;
        }
        void *p = realloc(b->data, capacity);
        if (!p) return -1;
        b->data = p;
        b->capacity = capacity;
    }
    if (size) memcpy(b->data + b->size, data, size);
    b->size += size;
    b->data[b->size] = 0;
    return 0;
}

static char *companion(struct database *db, const char *suffix)
{
    size_t length = strlen(db->base), extra = strlen(suffix);
    if (length > SIZE_MAX - extra - 1) { errno = ENOMEM; return NULL; }
    char *path = malloc(length + extra + 1);
    if (path) { memcpy(path, db->base, length); memcpy(path + length, suffix, extra + 1); }
    return path;
}

/* gzopen also reads uncompressed files, and validates gzip/dictzip checksums. */
static int read_file(struct database *db, const char *suffix, struct buffer *b)
{
    char *path = companion(db, suffix);
    if (!path) return -1;
    gzFile stream = gzopen(path, "rb");
    free(path);
    if (!stream) return -1;
    unsigned char chunk[65536];
    int count, rc = 0;
    while ((count = gzread(stream, chunk, sizeof(chunk))) > 0) {
        if (append(b, chunk, (size_t)count)) { rc = -1; break; }
    }
    if (count < 0) { errno = EINVAL; rc = -1; }
    if (gzclose(stream) != Z_OK) { errno = EINVAL; rc = -1; }
    return rc;
}

static uint64_t big_endian(const unsigned char *p, size_t bytes)
{
    uint64_t value = 0;
    while (bytes--) value = (value << 8) | *p++;
    return value;
}

static int number(const char *text, uint64_t *value)
{
    if (!text || *text < '0' || *text > '9') { errno = EINVAL; return -1; }
    char *end;
    errno = 0;
    uintmax_t n = strtoumax(text, &end, 10);
    if (errno || *end || n > UINT64_MAX) { errno = EINVAL; return -1; }
    *value = n;
    return 0;
}

static char *fold(const char *word)
{
    size_t size = strlen(word), length = 0;
    if (!size) return strdup("");
    if (u8_check((const uint8_t *)word, size)) { errno = EINVAL; return NULL; }
    uint8_t *text = u8_casefold((const uint8_t *)word, size, NULL, NULL, NULL, &length);
    if (!text) return NULL;
    char *terminated = realloc(text, length + 1);
    if (!terminated) { free(text); return NULL; }
    terminated[length] = 0;
    return terminated;
}

static int compare_heads(const void *a, const void *b)
{
    const struct headword *x = a, *y = b;
    int rc = strcmp(x->folded, y->folded);
    if (!rc) rc = strcmp(x->word, y->word);
    if (!rc) rc = (x->entry > y->entry) - (x->entry < y->entry);
    return rc;
}

static int close_database(dico_handle_t handle)
{
    struct database *db = (struct database *)handle;
    for (size_t i = 0; i < db->headword_count; i++) free(db->headwords[i].folded);
    free(db->headwords); free(db->entries); free(db->index); free(db->synonyms);
    free(db->metadata); free(db->info);
    if (db->data) munmap(db->data, db->data_size);
    if (db->fd >= 0) close(db->fd);
    if (db->compressed) gzclose(db->compressed);
    db->headwords = NULL; db->entries = NULL; db->index = db->synonyms = db->data = NULL;
    db->metadata = db->info = db->bookname = db->sequence = NULL;
    db->entry_count = db->headword_count = db->data_size = 0;
    db->compressed = NULL; db->fd = -1;
    return 0;
}

static int free_database(dico_handle_t handle)
{
    struct database *db = (struct database *)handle;
    close_database(handle);
    free(db->name); free(db->base); free(db);
    return 0;
}

static dico_handle_t init_database(const char *name, int argc, char **argv)
{
    if (argc != 2 || strlen(argv[1]) < 4 || strcmp(argv[1] + strlen(argv[1]) - 4, ".ifo")) {
        dico_log(L_ERR, 0, "StarDict %s: handler requires a .ifo pathname", name);
        return NULL;
    }
    struct database *db = calloc(1, sizeof(*db));
    if (!db) return NULL;
    db->fd = -1;
    db->name = strdup(name);
    db->base = strndup(argv[1], strlen(argv[1]) - 4);
    if (!db->name || !db->base) { free_database((dico_handle_t)db); return NULL; }
    return (dico_handle_t)db;
}

static int load_metadata(struct database *db, uint64_t *index_size, uint64_t *syn_count, size_t *offset_bytes)
{
    struct buffer b = {0};
    int rc = read_file(db, ".ifo", &b);
    db->metadata = (char *)b.data;
    if (rc) return -1;
    if (!b.size || u8_check(b.data, b.size)) { errno = EINVAL; return -1; }
    db->info = strdup(db->metadata);
    if (!db->info) return -1;
    char *line = db->metadata;
    if (b.size >= 3 && !memcmp(line, "\xef\xbb\xbf", 3)) line += 3;
    char *version = NULL, *count = NULL, *idx = NULL, *bits = NULL, *syn = NULL;
    bool first = true;
    while (line) {
        char *next = strchr(line, '\n');
        if (next) *next++ = 0;
        size_t size = strlen(line);
        if (size && line[size - 1] == '\r') line[size - 1] = 0;
        if (first) {
            if (strcmp(line, "StarDict's dict ifo file")) { errno = EINVAL; return -1; }
            first = false;
        } else {
            char *value = strchr(line, '=');
            if (value) {
                *value++ = 0;
                if (!strcmp(line, "version")) version = value;
                else if (!strcmp(line, "wordcount")) count = value;
                else if (!strcmp(line, "idxfilesize")) idx = value;
                else if (!strcmp(line, "idxoffsetbits")) bits = value;
                else if (!strcmp(line, "synwordcount")) syn = value;
                else if (!strcmp(line, "bookname")) db->bookname = value;
                else if (!strcmp(line, "sametypesequence")) db->sequence = value;
            }
        }
        line = next;
    }
    if (!version || (strcmp(version, "2.4.2") && strcmp(version, "3.0.0"))) { errno = EINVAL; return -1; }
    uint64_t entries, offset_bits = 32;
    if (number(count, &entries) || number(idx, index_size) ||
        (bits && number(bits, &offset_bits)) || (syn && number(syn, syn_count))) return -1;
    if ((offset_bits != 32 && offset_bits != 64) || entries > SIZE_MAX || *syn_count > SIZE_MAX) {
        errno = EINVAL; return -1;
    }
    db->entry_count = (size_t)entries;
    *offset_bytes = (size_t)(offset_bits / 8);
    if (!db->sequence) db->sequence = "";
    for (const char *p = db->sequence; *p; p++) {
        if (!((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z'))) { errno = EINVAL; return -1; }
    }
    return 0;
}

static int load_index(struct database *db, uint64_t index_size, uint64_t syn_count, size_t offset_bytes)
{
    struct buffer b = {0};
    int rc = read_file(db, ".idx", &b);
    if (rc && errno == ENOENT) rc = read_file(db, ".idx.gz", &b);
    db->index = b.data;
    if (rc) return -1;
    size_t record_size = offset_bytes + 4;
    if (b.size != index_size || db->entry_count > b.size / (record_size + 1) ||
        db->entry_count > SIZE_MAX / sizeof(*db->entries) ||
        syn_count > SIZE_MAX - db->entry_count ||
        db->entry_count + syn_count > SIZE_MAX / sizeof(*db->headwords)) { errno = EINVAL; return -1; }
    size_t heads = db->entry_count + (size_t)syn_count;
    if (db->entry_count && !(db->entries = calloc(db->entry_count, sizeof(*db->entries)))) return -1;
    if (heads && !(db->headwords = calloc(heads, sizeof(*db->headwords)))) return -1;
    db->headword_count = heads;
    size_t pos = 0, count = 0;
    while (pos < b.size) {
        unsigned char *end = memchr(b.data + pos, 0, b.size - pos);
        if (!end || b.size - (size_t)(end - b.data) - 1 < record_size || count >= db->entry_count) {
            errno = EINVAL; return -1;
        }
        struct entry *entry = &db->entries[count];
        entry->word = (char *)b.data + pos;
        entry->offset = big_endian(end + 1, offset_bytes);
        entry->size = (uint32_t)big_endian(end + 1 + offset_bytes, 4);
        db->headwords[count] = (struct headword){entry->word, fold(entry->word), count};
        if (!db->headwords[count].folded) return -1;
        count++;
        pos = (size_t)(end - b.data) + 1 + record_size;
    }
    if (count != db->entry_count) { errno = EINVAL; return -1; }
    b = (struct buffer){0};
    rc = read_file(db, ".syn", &b);
    db->synonyms = b.data;
    if (rc && !(errno == ENOENT && !syn_count)) return -1;
    pos = count = 0;
    while (pos < b.size) {
        unsigned char *end = memchr(b.data + pos, 0, b.size - pos);
        if (!end || b.size - (size_t)(end - b.data) - 1 < 4 || count >= syn_count) { errno = EINVAL; return -1; }
        uint64_t entry = big_endian(end + 1, 4);
        if (entry >= db->entry_count) { errno = EINVAL; return -1; }
        char *word = (char *)b.data + pos;
        struct headword *head = &db->headwords[db->entry_count + count];
        *head = (struct headword){word, fold(word), (size_t)entry};
        if (!head->folded) return -1;
        count++;
        pos = (size_t)(end - b.data) + 5;
    }
    if (count != syn_count) { errno = EINVAL; return -1; }
    if (heads > 1) qsort(db->headwords, heads, sizeof(*db->headwords), compare_heads);
    return 0;
}

static int load_data(struct database *db)
{
    char *path = companion(db, ".dict");
    if (!path) return -1;
    db->fd = open(path, O_RDONLY);
    free(path);
    if (db->fd >= 0) {
        struct stat st;
        if (fstat(db->fd, &st)) return -1;
        if (st.st_size < 0 || (uintmax_t)st.st_size > SIZE_MAX) { errno = EINVAL; return -1; }
        db->data_size = (size_t)st.st_size;
        if (db->data_size) {
            void *mapped = mmap(NULL, db->data_size, PROT_READ, MAP_PRIVATE, db->fd, 0);
            if (mapped == MAP_FAILED) return -1;
            db->data = mapped;
        }
    } else {
        if (errno != ENOENT) return -1;
        path = companion(db, ".dict.dz");
        if (!path) return -1;
        db->compressed = gzopen(path, "rb");
        free(path);
        if (!db->compressed) return -1;
    }
    for (size_t i = 0; i < db->entry_count; i++) {
        struct entry *entry = &db->entries[i];
        if (db->compressed ? (entry->offset > INT64_MAX || entry->size > (uint64_t)INT64_MAX - entry->offset) :
            (entry->offset > db->data_size || entry->size > db->data_size - entry->offset)) {
            errno = EINVAL; return -1;
        }
    }
    return 0;
}

static int open_database(dico_handle_t handle)
{
    struct database *db = (struct database *)handle;
    close_database(handle);
    uint64_t index_size = 0, syn_count = 0;
    size_t offset_bytes = 4;
    if (load_metadata(db, &index_size, &syn_count, &offset_bytes) ||
        load_index(db, index_size, syn_count, offset_bytes) || load_data(db)) {
        dico_log(L_ERR, errno, "StarDict %s: cannot load dictionary %s", db->name, db->base);
        close_database(handle);
        return 1;
    }
    return 0;
}

static int utf8_codepoint(struct buffer *b, uint32_t c)
{
    unsigned char text[4];
    size_t size;
    if (c < 0x80) { text[0] = (unsigned char)c; size = 1; }
    else if (c < 0x800) { text[0] = 0xc0 | (c >> 6); text[1] = 0x80 | (c & 0x3f); size = 2; }
    else if (c < 0x10000) {
        text[0] = 0xe0 | (c >> 12); text[1] = 0x80 | ((c >> 6) & 0x3f); text[2] = 0x80 | (c & 0x3f); size = 3;
    } else {
        text[0] = 0xf0 | (c >> 18); text[1] = 0x80 | ((c >> 12) & 0x3f);
        text[2] = 0x80 | ((c >> 6) & 0x3f); text[3] = 0x80 | (c & 0x3f); size = 4;
    }
    return append(b, text, size);
}

static bool ascii_alpha(unsigned char c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }
static bool ascii_digit(unsigned char c) { return c >= '0' && c <= '9'; }

/* Decode named and numeric HTML references, including HTML5 control mappings. */
static int entity(struct buffer *b, const unsigned char *data, size_t size, size_t *used)
{
    *used = 0;
    if (size < 2 || data[0] != '&') return 0;
    if (data[1] == '#') {
        size_t pos = 2;
        unsigned base = 10;
        if (pos < size && (data[pos] == 'x' || data[pos] == 'X')) { base = 16; pos++; }
        size_t start = pos;
        uint32_t c = 0;
        while (pos < size) {
            unsigned digit;
            if (ascii_digit(data[pos])) digit = data[pos] - '0';
            else if (base == 16 && data[pos] >= 'a' && data[pos] <= 'f') digit = data[pos] - 'a' + 10;
            else if (base == 16 && data[pos] >= 'A' && data[pos] <= 'F') digit = data[pos] - 'A' + 10;
            else break;
            if (c <= 0x110000) c = c * base + digit;
            pos++;
        }
        if (pos == start) return 0;
        if (pos < size && data[pos] == ';') pos++;
        *used = pos;
        if (c < sizeof(html_numeric_controls) / sizeof(*html_numeric_controls))
            return append(b, html_numeric_controls[c], strlen(html_numeric_controls[c]));
        if (c > 0x10ffff || (c >= 0xd800 && c <= 0xdfff)) c = 0xfffd;
        if ((c >= 0xfdd0 && c <= 0xfdef) || (c & 0xffff) >= 0xfffe) return 0;
        return utf8_codepoint(b, c);
    }
    char name[64];
    size_t length = 0;
    while (length + 1 < size && length + 1 < sizeof(name) &&
        (ascii_alpha(data[length + 1]) || ascii_digit(data[length + 1]) || data[length + 1] == ';')) {
        name[length] = (char)data[length + 1];
        length++;
        if (name[length - 1] == ';') break;
    }
    while (length) {
        name[length] = 0;
        size_t lo = 0, hi = sizeof(html_entities) / sizeof(*html_entities);
        while (lo < hi) {
            size_t mid = lo + (hi - lo) / 2;
            int rc = strcmp(name, html_entities[mid].name);
            if (rc > 0) lo = mid + 1; else hi = mid;
        }
        if (lo < sizeof(html_entities) / sizeof(*html_entities) && !strcmp(name, html_entities[lo].name)) {
            *used = length + 1;
            return append(b, html_entities[lo].value, strlen(html_entities[lo].value));
        }
        length--;
    }
    return 0;
}

static int strip_markup(struct buffer *b, const unsigned char *data, size_t size)
{
    size_t pos = 0;
    while (pos < size) {
        if (data[pos] == '&') {
            size_t used;
            if (entity(b, data + pos, size - pos, &used)) return -1;
            if (used) { pos += used; continue; }
        }
        if (data[pos] == '<' && pos + 1 < size &&
            (ascii_alpha(data[pos + 1]) || data[pos + 1] == '/' || data[pos + 1] == '!' || data[pos + 1] == '?')) {
            if (size - pos >= 4 && !memcmp(data + pos, "<!--", 4)) {
                pos += 4;
                while (size - pos >= 3 && memcmp(data + pos, "-->", 3)) pos++;
                pos = size - pos >= 3 ? pos + 3 : size;
                continue;
            }
            size_t start = pos + 1, end = start;
            unsigned char quote = 0;
            while (end < size) {
                unsigned char c = data[end];
                if (quote) { if (c == quote) quote = 0; }
                else if (c == '\'' || c == '"') quote = c;
                else if (c == '>') break;
                end++;
            }
            if (end < size) {
                bool closing = data[start] == '/';
                if (closing) start++;
                char tag[16];
                size_t length = 0;
                while (start < end && ascii_alpha(data[start])) {
                    if (length + 1 < sizeof(tag)) {
                        unsigned char c = data[start];
                        tag[length++] = (char)(c >= 'A' && c <= 'Z' ? c + ('a' - 'A') : c);
                    }
                    start++;
                }
                tag[length] = 0;
                bool block = !strcmp(tag, "p") || !strcmp(tag, "div") || !strcmp(tag, "li") || !strcmp(tag, "tr");
                if ((block || (!closing && !strcmp(tag, "br"))) && append(b, "\n", 1)) return -1;
                if (!closing && block && end > pos && data[end - 1] == '/' && append(b, "\n", 1)) return -1;
                pos = end + 1;
                continue;
            }
        }
        if (append(b, data + pos, 1)) return -1;
        pos++;
    }
    return 0;
}

static int render_field(struct buffer *output, unsigned char kind, const unsigned char *data, size_t size)
{
    struct buffer field = {0};
    int rc;
    if (kind >= 'A' && kind <= 'Z') {
        char text[80];
        int length = snprintf(text, sizeof(text), "[binary field %c: %zu bytes]", kind, size);
        rc = append(&field, text, (size_t)length);
    } else {
        if (size && u8_check(data, size)) { errno = EINVAL; return -1; }
        rc = kind == 'h' || kind == 'g' || kind == 'x' ? strip_markup(&field, data, size) : append(&field, data, size);
    }
    size_t start = 0, end = field.size;
    while (start < end && (field.data[start] == 0 || field.data[start] == '\r' || field.data[start] == '\n')) start++;
    while (end > start && (field.data[end - 1] == 0 || field.data[end - 1] == '\r' || field.data[end - 1] == '\n')) end--;
    if (!rc && end > start) {
        if (output->size) rc = append(output, "\n", 1);
        if (!rc) rc = append(output, field.data + start, end - start);
    }
    free(field.data);
    return rc;
}

static int render_article(struct database *db, const unsigned char *data, size_t size, struct buffer *output)
{
    size_t pos = 0, field = 0, sequence_size = strlen(db->sequence);
    while (pos < size || field < sequence_size) {
        unsigned char kind;
        bool last = false;
        if (sequence_size) {
            if (field >= sequence_size) { errno = EINVAL; return -1; }
            kind = (unsigned char)db->sequence[field];
            last = field + 1 == sequence_size;
        } else kind = data[pos++];
        if (!ascii_alpha(kind)) { errno = EINVAL; return -1; }
        bool lower = kind >= 'a' && kind <= 'z';
        size_t length;
        if (last) length = size - pos;
        else if (lower) {
            const unsigned char *end = pos < size ? memchr(data + pos, 0, size - pos) : NULL;
            if (!end) { errno = EINVAL; return -1; }
            length = (size_t)(end - data) - pos;
        } else {
            if (size - pos < 4) { errno = EINVAL; return -1; }
            length = (size_t)big_endian(data + pos, 4);
            pos += 4;
            if (length > size - pos) { errno = EINVAL; return -1; }
        }
        if (render_field(output, kind, data ? data + pos : NULL, length)) return -1;
        pos += length + (lower && !last);
        field++;
    }
    return 0;
}

static void free_result(dico_result_t handle)
{
    struct result *result = (struct result *)handle;
    if (result) { free(result->items); free(result); }
}

static int add_result(struct result *result, size_t item)
{
    if (result->count == result->capacity) {
        size_t capacity = result->capacity ? result->capacity * 2 : 16;
        if (capacity < result->capacity || capacity > SIZE_MAX / sizeof(*result->items)) {
            errno = ENOMEM; return -1;
        }
        void *items = realloc(result->items, capacity * sizeof(*result->items));
        if (!items) return -1;
        result->items = items;
        result->capacity = capacity;
    }
    result->items[result->count++] = item;
    return 0;
}

static size_t lower_bound(struct result *result, const char *word)
{
    size_t lo = 0, hi = result->db->headword_count;
    while (lo < hi) {
        size_t mid = lo + (hi - lo) / 2;
        result->comparisons++;
        if (strcmp(result->db->headwords[mid].folded, word) < 0) lo = mid + 1;
        else hi = mid;
    }
    return lo;
}

static int compare_ids(const void *a, const void *b)
{
    size_t x = *(const size_t *)a, y = *(const size_t *)b;
    return (x > y) - (x < y);
}

static dico_result_t define_word(dico_handle_t handle, const char *word)
{
    struct database *db = (struct database *)handle;
    struct result *result = calloc(1, sizeof(*result));
    char *folded = fold(word);
    if (!result || !folded) { free(result); free(folded); return NULL; }
    result->db = db;
    result->definitions = true;
    int rc = 0;
    for (size_t i = lower_bound(result, folded); i < db->headword_count; i++) {
        result->comparisons++;
        if (strcmp(db->headwords[i].folded, folded)) break;
        if ((rc = add_result(result, db->headwords[i].entry))) break;
    }
    free(folded);
    if (rc || !result->count) { free_result((dico_result_t)result); return NULL; }
    /* A synonym can refer to an entry already found under its canonical name. */
    qsort(result->items, result->count, sizeof(*result->items), compare_ids);
    size_t unique = 1;
    for (size_t i = 1; i < result->count; i++)
        if (result->items[i] != result->items[unique - 1]) result->items[unique++] = result->items[i];
    result->count = unique;
    return (dico_result_t)result;
}

static dico_result_t match_word(dico_handle_t handle, const dico_strategy_t strategy, const char *word)
{
    struct database *db = (struct database *)handle;
    struct result *result = calloc(1, sizeof(*result));
    char *folded = fold(word);
    if (!result || !folded) { free(result); free(folded); return NULL; }
    result->db = db;
    bool exact = !strcmp(strategy->name, "exact"), prefix = !strcmp(strategy->name, "prefix");
    bool suffix = !strcmp(strategy->name, "suffix"), substring = !strcmp(strategy->name, "substring");
    bool generic = !(exact || prefix || suffix || substring);
    struct dico_key key = {0};
    if (generic && (!strategy->sel || dico_key_init(&key, strategy, word))) {
        /* Dico leaves key.word allocated when a selector rejects its key. */
        free(key.word); free(folded); free_result((dico_result_t)result); return NULL;
    }
    size_t length = strlen(folded), start = exact || prefix ? lower_bound(result, folded) : 0;
    int rc = 0;
    for (size_t i = start; i < db->headword_count; i++) {
        struct headword *head = &db->headwords[i];
        if (i > start && !strcmp(head->word, db->headwords[i - 1].word)) continue;
        result->comparisons++;
        bool matched;
        if (exact || prefix) {
            matched = exact ? !strcmp(head->folded, folded) : !strncmp(head->folded, folded, length);
            if (!matched) break;
        } else if (suffix) {
            size_t size = strlen(head->folded);
            matched = size >= length && !strcmp(head->folded + size - length, folded);
        } else if (substring) matched = strstr(head->folded, folded) != NULL;
        else {
            int selected = dico_key_match(&key, head->word);
            if (selected < 0) { rc = -1; break; }
            matched = selected != 0;
        }
        if (matched && (rc = add_result(result, i))) break;
    }
    if (generic) dico_key_deinit(&key);
    free(folded);
    if (rc || !result->count) { free_result((dico_result_t)result); return NULL; }
    return (dico_result_t)result;
}

static int read_article(struct database *db, const struct entry *entry, struct buffer *storage,
                        const unsigned char **data)
{
    if (!db->compressed) {
        *data = entry->size ? db->data + (size_t)entry->offset : NULL;
        return 0;
    }
    if (gzseek(db->compressed, (z_off_t)entry->offset, SEEK_SET) < 0) { errno = EINVAL; return -1; }
    size_t remaining = entry->size;
    unsigned char chunk[65536];
    while (remaining) {
        unsigned amount = remaining < sizeof(chunk) ? (unsigned)remaining : sizeof(chunk);
        int count = gzread(db->compressed, chunk, amount);
        if (count <= 0) { errno = EINVAL; return -1; }
        if (append(storage, chunk, (size_t)count)) return -1;
        remaining -= (size_t)count;
    }
    *data = storage->data;
    return 0;
}

static int output_result(dico_result_t handle, size_t n, dico_stream_t stream)
{
    struct result *result = (struct result *)handle;
    if (n >= result->count) return EINVAL;
    struct database *db = result->db;
    size_t item = result->items[n];
    if (!result->definitions) {
        const char *word = db->headwords[item].word;
        /* dicod supplies the outer quotes but leaves escaping to the module. */
        const char *start = word;
        for (const char *p = word; *p; p++) {
            if (*p == '"' || *p == '\\') {
                int rc = dico_stream_write(stream, start, (size_t)(p - start));
                if (!rc) rc = dico_stream_write(stream, "\\", 1);
                if (rc) return rc;
                start = p;
            }
        }
        return dico_stream_write(stream, start, strlen(start));
    }
    const struct entry *entry = &db->entries[item];
    struct buffer storage = {0}, output = {0};
    const unsigned char *data = NULL;
    int rc = read_article(db, entry, &storage, &data);
    if (!rc) rc = render_article(db, data, entry->size, &output);
    if (rc) {
        dico_log(L_ERR, errno, "StarDict %s: invalid article for %s", db->name, entry->word);
        rc = EINVAL;
    } else {
        rc = dico_stream_writeln(stream, entry->word, strlen(entry->word));
        if (!rc && output.size) rc = dico_stream_writeln(stream, (char *)output.data, output.size);
    }
    free(storage.data); free(output.data);
    return rc;
}

static size_t result_count(dico_result_t handle) { return ((struct result *)handle)->count; }
static size_t comparison_count(dico_result_t handle) { return ((struct result *)handle)->comparisons; }
static char *db_info(dico_handle_t handle) { return strdup(((struct database *)handle)->info); }
static char *db_description(dico_handle_t handle)
{
    struct database *db = (struct database *)handle;
    return strdup(db->bookname ? db->bookname : db->name);
}
static char *mime_header(dico_handle_t handle DICO_ARG_UNUSED)
{
    return strdup("Content-Type: text/plain; charset=utf-8\nContent-Transfer-Encoding: 8bit\n");
}
static int result_headers(dico_result_t handle DICO_ARG_UNUSED, dico_assoc_list_t headers)
{
    int rc = dico_assoc_add(headers, "Content-Type", "text/plain; charset=utf-8", 1, 1);
    return rc ? rc : dico_assoc_add(headers, "Content-Transfer-Encoding", "8bit", 1, 1);
}

static int init_module(int argc DICO_ARG_UNUSED, char **argv DICO_ARG_UNUSED)
{
    static struct dico_strategy substring = { .name = "substring", .descr = "Match word substrings" };
    if (!dico_strategy_find(substring.name)) return dico_strategy_add(&substring);
    return 0;
}

struct dico_database_module DICO_EXPORT(stardict, module) = {
    .dico_version = DICO_MODULE_VERSION,
    .dico_capabilities = DICO_CAPA_NONE,
    .dico_init = init_module,
    .dico_init_db = init_database,
    .dico_free_db = free_database,
    .dico_open = open_database,
    .dico_close = close_database,
    .dico_db_info = db_info,
    .dico_db_descr = db_description,
    .dico_match = match_word,
    .dico_define = define_word,
    .dico_output_result = output_result,
    .dico_result_count = result_count,
    .dico_compare_count = comparison_count,
    .dico_free_result = free_result,
    .dico_result_headers = result_headers,
    .dico_db_mime_header = mime_header,
};
