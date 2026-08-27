package json_parser

TokenType :: enum {
	ERROR,
	LEFT_BRACE,
	RIGHT_BRACE,
	LEFT_BRACKET,
	RIGHT_BRACKET,
	STRING,
	NUMBER,
	TRUE,
	FALSE,
	NULL,
	COLON,
	COMMA,
	EOF,
}

Token :: struct {
	type:   TokenType,
	lexeme: string,
	error:  string,
}

Lexer :: struct {
	source:  string,
	start:   int,
	current: int,
}

@(private)
lexer_make :: proc(source: string) -> Lexer {
	return Lexer{source = source}
}

@(private)
scan_token :: proc(l: ^Lexer) -> Token {
	if len(l.source) == 0 do return Token{type = .ERROR, error = "Empty JSON source"}

	for {
		if lexer_is_at_end(l) {
			return Token{type = .EOF}
		}

		l.start = l.current

		char := lexer_advance(l)

		switch char {
		case ' ', '\r', '\t', '\n': // skip
		case '{':
			return token_make(l, .LEFT_BRACE)
		case '}':
			return token_make(l, .RIGHT_BRACE)
		case '[':
			return token_make(l, .LEFT_BRACKET)
		case ']':
			return token_make(l, .RIGHT_BRACKET)
		case ':':
			return token_make(l, .COLON)
		case ',':
			return token_make(l, .COMMA)
		case '"':
			return string_lexeme(l)
		case '-', '0' ..= '9':
			return number_lexeme(l)
		case 't', 'f', 'n':
			return keyword_lexeme(l)
		case:
			return error_lexeme(l, "Invalid character")
		}
	}
}

@(private)
token_make :: proc(l: ^Lexer, type: TokenType) -> Token {
	return Token{type = type, lexeme = l.source[l.start:l.current]}
}

@(private)
error_lexeme :: proc(l: ^Lexer, message: string) -> Token {
	return Token{type = .ERROR, lexeme = l.source[l.start:l.current], error = message}
}

lexer_advance :: proc(l: ^Lexer) -> byte {
	char := l.source[l.current]
	l.current += 1
	return char
}

string_lexeme :: proc(l: ^Lexer) -> Token {
	for lexer_peek(l) != '"' && !lexer_is_at_end(l) {
		c := lexer_peek(l)
		if c == '\n' || c == '\r' || c == '\t' {
			return error_lexeme(l, "Invalid character in string")
		}
		if c == '\\' {
			lexer_advance(l)
			switch lexer_peek(l) {
			case '"', '\\', '/', 'b', 'f', 'n', 'r', 't', 'u':
			case:
				return error_lexeme(l, "Invalid string escape")
			}
		}
		lexer_advance(l)
	}

	if lexer_is_at_end(l) {
		return error_lexeme(l, "Unterminated string")
	}

	lexer_advance(l)

	value := l.source[l.start + 1:l.current - 1]
	return Token{type = .STRING, lexeme = value}
}

lexer_peek :: proc(l: ^Lexer) -> byte {
	if lexer_is_at_end(l) do return 0
	return l.source[l.current]
}

lexer_is_at_end :: proc(l: ^Lexer) -> bool {
	return l.current >= len(l.source)
}

keyword_lexeme :: proc(l: ^Lexer) -> Token {
	for c := lexer_peek(l); (c >= 'a' && c <= 'z') && !lexer_is_at_end(l); c = lexer_peek(l) {
		lexer_advance(l)
	}

	switch l.source[l.start:l.current] {
	case "true":
		return token_make(l, .TRUE)
	case "false":
		return token_make(l, .FALSE)
	case "null":
		return token_make(l, .NULL)
	}

	return error_lexeme(l, "Invalid keyword")
}

number_lexeme :: proc(l: ^Lexer) -> Token {
	first := l.source[l.start]
	if first == '-' {
		if lexer_is_at_end(l) do return error_lexeme(l, "Invalid number")
		first = lexer_peek(l)
		lexer_advance(l)
	}
	if first < '0' || first > '9' do return error_lexeme(l, "Invalid number")

	if first != '0' {
		for c := lexer_peek(l); c >= '0' && c <= '9'; c = lexer_peek(l) {
			lexer_advance(l)
		}
	} else if c := lexer_peek(l); c >= '0' && c <= '9' {
		lexer_advance(l)
		return error_lexeme(l, "Invalid number")
	}

	if lexer_peek(l) == '.' {
		lexer_advance(l)
		if c := lexer_peek(l); c < '0' || c > '9' {
			return error_lexeme(l, "Invalid number")
		}
		for c := lexer_peek(l); c >= '0' && c <= '9'; c = lexer_peek(l) {
			lexer_advance(l)
		}
	}

	if e := lexer_peek(l); e == 'e' || e == 'E' {
		lexer_advance(l)
		if s := lexer_peek(l); s == '+' || s == '-' {
			lexer_advance(l)
		}
		if lexer_peek(l) < '0' || lexer_peek(l) > '9' {
			return error_lexeme(l, "Invalid number")
		}
		for c := lexer_peek(l); c >= '0' && c <= '9'; c = lexer_peek(l) {
			lexer_advance(l)
		}
	}

	return Token{type = .NUMBER, lexeme = l.source[l.start:l.current]}
}
