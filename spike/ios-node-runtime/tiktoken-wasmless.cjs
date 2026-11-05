'use strict';

const jsTiktoken = require('js-tiktoken');

const textEncoder = new TextEncoder();

function concatTokenBytes(tokenBytes) {
    const size = tokenBytes.reduce((total, bytes) => total + bytes.length, 0);
    const merged = new Uint8Array(size);
    let offset = 0;

    for (const bytes of tokenBytes) {
        merged.set(bytes, offset);
        offset += bytes.length;
    }

    return merged;
}

class Tiktoken {
    constructor(inner, name) {
        this.inner = inner;
        this.name = name;
    }

    encode(text, allowedSpecial = [], disallowedSpecial = 'all') {
        return Uint32Array.from(
            this.inner.encode(text, allowedSpecial, disallowedSpecial),
        );
    }

    encode_ordinary(text) {
        return Uint32Array.from(this.inner.encode(text, [], []));
    }

    encode_with_unstable(text, allowedSpecial = [], disallowedSpecial = 'all') {
        return {
            tokens: this.encode(text, allowedSpecial, disallowedSpecial),
            possibleUnstableBytes: new Uint8Array(),
        };
    }

    encode_single_token(bytes) {
        const rank = this.inner.rankMap.get(Uint8Array.from(bytes).join(','));
        if (rank === undefined) {
            throw new Error('Token is not in the encoding');
        }
        return rank;
    }

    decode(tokens) {
        const values = [];

        for (const token of tokens) {
            const bytes = this.inner.textMap.get(token)
                ?? this.inner.inverseSpecialTokens[token];
            if (bytes !== undefined) {
                values.push(bytes);
            }
        }

        return concatTokenBytes(values);
    }

    decode_single_token_bytes(token) {
        return this.decode(new Uint32Array([token]));
    }

    token_byte_values() {
        const highestToken = Math.max(
            0,
            ...this.inner.textMap.keys(),
            ...Object.keys(this.inner.inverseSpecialTokens).map(Number),
        );
        const values = new Array(highestToken + 1);

        for (const [token, bytes] of this.inner.textMap) {
            values[token] = Array.from(bytes);
        }
        for (const [token, bytes] of Object.entries(
            this.inner.inverseSpecialTokens,
        )) {
            values[Number(token)] = Array.from(bytes);
        }

        return values;
    }

    free() {}
}

function wrap(inner, name) {
    return new Tiktoken(inner, name);
}

function get_encoding(encoding, extendSpecialTokens) {
    return wrap(
        jsTiktoken.getEncoding(encoding, extendSpecialTokens),
        encoding,
    );
}

function encoding_for_model(model, extendSpecialTokens) {
    const encoding = jsTiktoken.getEncodingNameForModel(model);
    return wrap(
        jsTiktoken.getEncoding(encoding, extendSpecialTokens),
        encoding,
    );
}

function get_encoding_name_for_model(model) {
    return jsTiktoken.getEncodingNameForModel(model);
}

module.exports = {
    Tiktoken,
    encoding_for_model,
    get_encoding,
    get_encoding_name_for_model,
};
