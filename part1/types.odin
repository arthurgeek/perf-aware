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
