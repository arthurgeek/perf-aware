package json_parser

import "core:fmt"
import "core:strconv"

Parser :: struct {
	lexer:     Lexer,
	current:   Token,
	previous:  Token,
	had_error: bool,
}

parser_make :: proc(source: string) -> Parser {
	p := Parser {
		lexer = lexer_make(source),
	}
	p.current = scan_token(&p.lexer)
	if p.current.type == .ERROR {
		parser_error(&p, p.current, p.current.error)
	}
	return p
}

parser_error :: proc(p: ^Parser, token: Token, message: string) {
	if p.had_error do return
	fmt.eprintln(fmt.tprintf("ERROR: \"%s\" - %s", token.lexeme, message))
	p.had_error = true
}

@(private)
parse :: proc(p: ^Parser) -> bool {
	tok := parser_peek(p)
	if tok.type != .LEFT_BRACE && tok.type != .LEFT_BRACKET {
		parser_error(p, tok, "Expected object or array root")
		return false
	}

	value(p)

	if !parser_is_at_end(p) {
		tok = parser_peek(p)
		parser_error(p, tok, "Unexpected content after root value")
	}

	return !p.had_error
}

@(private)
value :: proc(p: ^Parser) {
	token := parser_peek(p)

	#partial switch token.type {
	case .LEFT_BRACE:
		object(p)
		return
	case .LEFT_BRACKET:
		array(p)
		return
	case .STRING, .NUMBER, .TRUE, .FALSE, .NULL:
		parser_advance(p)
		return
	}

	parser_error(p, token, "Expected JSON value")
}

skip_json_value :: proc(p: ^Parser) {
	value(p)
}

@(private)
object :: proc(p: ^Parser) {
	parser_advance(p)

	if !check(p, .RIGHT_BRACE) {
		for !p.had_error {
			consume(p, .STRING, "Expected object field name")
			consume(p, .COLON, "Expected colon after field name")
			value(p)

			if !match(p, .COMMA) {
				break
			}
		}
	}

	consume(p, .RIGHT_BRACE, "Expected closing brace")
}

@(private)
array :: proc(p: ^Parser) {
	parser_advance(p)

	if !check(p, .RIGHT_BRACKET) {
		for !p.had_error {
			value(p)

			if !match(p, .COMMA) {
				break
			}
		}
	}

	consume(p, .RIGHT_BRACKET, "Expected closing bracket")
}

consume :: proc(p: ^Parser, type: TokenType, message: string) -> Token {
	if check(p, type) {
		return parser_advance(p)
	}

	tok := parser_peek(p)
	parser_error(p, tok, message)
	return tok
}

consume_string :: proc(p: ^Parser, message: string) -> (string, bool) {
	token := consume(p, .STRING, message)
	if p.had_error do return "", false
	return token.lexeme, true
}

consume_number :: proc(p: ^Parser, message: string) -> (f64, bool) {
	token := consume(p, .NUMBER, message)
	if p.had_error do return 0, false

	value, ok := strconv.parse_f64(token.lexeme)
	if !ok {
		parser_error(p, token, message)
		return 0, false
	}
	return value, true
}

match :: proc(p: ^Parser, type: TokenType) -> bool {
	if check(p, type) {
		parser_advance(p)
		return true
	}
	return false
}

check :: proc(p: ^Parser, type: TokenType) -> bool {
	if parser_is_at_end(p) {
		return false
	}

	return parser_peek(p).type == type
}

@(private)
parser_advance :: proc(p: ^Parser) -> Token {
	if !parser_is_at_end(p) && !p.had_error {
		p.previous = p.current
		p.current = scan_token(&p.lexer)
		if p.current.type == .ERROR {
			parser_error(p, p.current, p.current.error)
		}
	}

	return previous(p)
}

@(private)
parser_is_at_end :: proc(p: ^Parser) -> bool {
	return parser_peek(p).type == .EOF
}

parser_peek :: proc(p: ^Parser) -> Token {
	return p.current
}

@(private)
previous :: proc(p: ^Parser) -> Token {
	return p.previous
}

validate_source :: proc(source: string) -> bool {
	parser := parser_make(source)
	if parser.had_error do return false
	return parse(&parser)
}

finish :: proc(p: ^Parser) -> bool {
	if p.had_error do return false
	if !parser_is_at_end(p) {
		parser_error(p, parser_peek(p), "Unexpected content after root value")
	}
	return !p.had_error
}
