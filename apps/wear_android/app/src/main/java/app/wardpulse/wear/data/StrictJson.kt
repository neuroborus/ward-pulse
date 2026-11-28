package app.wardpulse.wear.data

import org.json.JSONObject

/**
 * Parses [text] as one complete RFC 8259 object. Android's `JSONObject(String)` is lenient: it
 * stops after the first value and accepts comments, unquoted names and single quotes. Here the
 * whole document must be strict JSON with unique member names, or this throws.
 */
internal fun strictJsonObject(text: String): JSONObject {
    StrictJsonReader(text).document()
    return JSONObject(text)
}

private class StrictJsonReader(private val text: String) {
    private var position = 0

    fun document() {
        whitespace()
        require(peek() == '{')
        value(depth = 0)
        whitespace()
        require(position == text.length) { "trailing content" }
    }

    private fun value(depth: Int) {
        require(depth < MAX_DEPTH)
        when (peek()) {
            '{' -> members(depth + 1)
            '[' -> elements(depth + 1)
            '"' -> string()
            't' -> literal("true")
            'f' -> literal("false")
            'n' -> literal("null")
            else -> number()
        }
    }

    private fun members(depth: Int) {
        expect('{')
        whitespace()
        if (peek() == '}') {
            position++
            return
        }
        val names = HashSet<String>()
        while (true) {
            whitespace()
            require(names.add(string())) { "duplicate member" }
            whitespace()
            expect(':')
            whitespace()
            value(depth)
            whitespace()
            if (next() == '}') return
            require(text[position - 1] == ',')
        }
    }

    private fun elements(depth: Int) {
        expect('[')
        whitespace()
        if (peek() == ']') {
            position++
            return
        }
        while (true) {
            whitespace()
            value(depth)
            whitespace()
            if (next() == ']') return
            require(text[position - 1] == ',')
        }
    }

    private fun string(): String {
        expect('"')
        val value = StringBuilder()
        while (true) {
            val char = next()
            when {
                char == '"' -> return value.toString()
                char == '\\' -> when (val escaped = next()) {
                    '"', '\\', '/' -> value.append(escaped)
                    'b' -> value.append('\b')
                    'f' -> value.append('\u000c')
                    'n' -> value.append('\n')
                    'r' -> value.append('\r')
                    't' -> value.append('\t')
                    'u' -> {
                        val hex = text.substring(position, minOf(position + 4, text.length))
                        require(hex.length == 4 && hex.all { it.isHexDigit() })
                        value.append(hex.toInt(16).toChar())
                        position += 4
                    }
                    else -> throw IllegalArgumentException("invalid escape")
                }
                char < ' ' -> throw IllegalArgumentException("control character")
                else -> value.append(char)
            }
        }
    }

    private fun number() {
        if (peek() == '-') position++
        if (peek() == '0') position++ else digits()
        if (peek() == '.') {
            position++
            digits()
        }
        if (peek() == 'e' || peek() == 'E') {
            position++
            if (peek() == '+' || peek() == '-') position++
            digits()
        }
    }

    private fun digits() {
        val start = position
        while (peek()?.let { it in '0'..'9' } == true) position++
        require(position > start)
    }

    private fun literal(word: String) {
        require(text.startsWith(word, position))
        position += word.length
    }

    private fun whitespace() {
        while (peek() == ' ' || peek() == '\t' || peek() == '\n' || peek() == '\r') position++
    }

    private fun expect(char: Char) = require(next() == char)

    private fun next(): Char {
        require(position < text.length) { "truncated" }
        return text[position++]
    }

    private fun peek(): Char? = text.getOrNull(position)

    private fun Char.isHexDigit() = this in '0'..'9' || this in 'a'..'f' || this in 'A'..'F'

    private companion object {
        const val MAX_DEPTH = 32
    }
}
