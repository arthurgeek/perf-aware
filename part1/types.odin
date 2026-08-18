package sim8086

// enum value names are the mnemonics: %v prints them directly
Op :: enum {
	none,
	mov,
	add,
	sub,
	cmp,
	jo,
	jno,
	jb,
	jnb,
	je,
	jne,
	jbe,
	ja,
	js,
	jns,
	jp,
	jnp,
	jl,
	jnl,
	jle,
	jg,
	loopnz,
	loopz,
	loop,
	jcxz,
}

RegisterIndex :: distinct byte
EABase :: distinct byte

reg_encoding := [8][2]string {
	{"al", "ax"},
	{"cl", "cx"},
	{"dl", "dx"},
	{"bl", "bx"},
	{"ah", "sp"},
	{"ch", "bp"},
	{"dh", "si"},
	{"bh", "di"},
}

rm_encoding := [8]string{"bx+si", "bx+di", "bp+si", "bp+di", "si", "di", "bp", "bx"}

ea_base_registers := [8][]RegisterIndex {
	0b010 = {0b101, 0b110},
	0b111 = {0b011},
}

Register :: struct {
	index: RegisterIndex,
	wide:  bool,
}

EffectiveAddress :: struct {
	base: EABase,
	disp: i16,
}

DirectAddress :: distinct u16
Immediate :: distinct i16
JumpOffset :: distinct i8

Operand :: union {
	Register,
	EffectiveAddress,
	DirectAddress,
	Immediate,
	JumpOffset,
}

Instruction :: struct {
	op:   Op,
	dst:  Operand,
	src:  Operand,
	wide: bool,
}
