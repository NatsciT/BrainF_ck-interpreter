.386
.MODEL		FLAT, STDCALL
OPTION		CASEMAP:NONE

INCLUDE		C:\masm32\include\msvcrt.inc
INCLUDE		C:\masm32\include\kernel32.inc
INCLUDE		C:\masm32\include\shell32.inc

INCLUDELIB	C:\masm32\lib\msvcrt.lib
INCLUDELIB	C:\masm32\lib\kernel32.lib
INCLUDELIB	C:\masm32\lib\shell32.lib

.DATA
	IncorrectArgumentsErrorMsg	db 13, 10, "Incorrect arguments.", 0
	FailedToAllocMemory			db 13, 10, "Failed to allocated memory.", 0
	OutOfBound					db 13, 10, "Referenced address is out of bound.", 0
	InvalidInstruction			db 13, 10, "Argument contains one or more invalid instruction(s).", 0
	UnknownError				db 13, 10, "Unknown error.", 0

	OperationEndedSuccessfully	db 13, 10, "Execution ended successfully", 0

.CODE
interpret PROC
	; ebp+8 : address to the input instructions
	; ebp-4 : pointer to allocated memory

	; return 0 on success
	; return 1 on memory allocation failure
	; return 2 when bf pointer moves out of bound
	; return 3 when invalid instruction is included

	; read the instruction
	; > (3e, addptr) :		포인터 증가
	; < (3c, subptr) :		포인터 감소
	; + (2b, addval) :		포인터가 가리키는 바이트의 값을 증가
	; - (2d, subval) :		포인터가 가리키는 바이트의 값을 감소
	; . (2e, printv) :		포인터가 가리키는 바이트 값을 아스키 코드 문자로 출력한다.
	; , (2c, inputv) :		포인터가 가리키는 바이트에 아스키 코드 값을 입력한다.
	; [ (5b, viszero) :		포인터가 가리키는 바이트의 값이 0이 되면 짝이 되는 ]로 이동한다.
	; ] (5d, visntzero) :	포인터가 가리키는 바이트의 값이 0이 아니면 짝이 되는 [로 이동한다.

	; prologue
	push ebp
	mov ebp, esp
	sub esp, 4

	; calloc
	invoke crt_calloc, 1, 65536		; 64KB
	test eax, eax
	je interpret_failed_to_alloc_mem
	mov dword ptr [ebp-4], eax

	; setup bf pointer (saved in di)
	xor edi, edi

interpret_loop:
	; check if end of instruction
	; and move the instruction to bl
	mov esi, dword ptr [ebp+8]
	mov bl, byte ptr [esi]
	test bl, bl
	je interpret_good_exit

	; add instruction pointer
	add dword ptr [ebp+8], 2

	; load address of the allocated memory in esi
	mov esi, dword ptr [ebp-4]

	; figure out which instruction it is
	sub bl, 2Bh
	je addval		; 2b
	sub bl, 1h
	je inputv		; 2c
	sub bl, 1h
	je subval		; 2d
	sub bl, 1h
	je printv		; 2e
	sub bl, 0Eh
	je subptr		; 3c
	sub bl, 2h
	je addptr		; 3e
	sub bl, 1Dh
	je viszero		; 5b
	sub bl, 2h
	je visntzero	; 5d
	jmp interpret_loop

addptr:
	add di, 1
	jc interpret_out_of_bound
	jmp interpret_loop

subptr:
	sub di, 1
	jc interpret_out_of_bound
	jmp interpret_loop

addval:
	inc dword ptr [esi + edi]
	jmp interpret_loop

subval:
	dec dword ptr [esi + edi]
	jmp interpret_loop

printv:
	movzx esi, byte ptr [esi + edi]
	invoke crt_putchar, esi
	jmp interpret_loop

inputv:
	invoke crt_getchar
	mov esi, dword ptr [ebp-4]
	mov byte ptr [esi + edi], al
	jmp interpret_loop

; ############################ TO FIX

viszero:
	xor ecx, ecx
	inc ecx
	movzx bx, byte ptr [esi + edi]
	test bx, bx
	je viszero_jump
	jmp interpret_loop

viszero_jump:
	add dword ptr [ebp+8], 2
	mov esi, dword ptr [ebp+8]
	mov bl, byte ptr [esi]
	cmp bl, 5Dh
	je viszero_rightbracket
	cmp bl, 5Bh
	je viszero_leftbracket
	jmp viszero_jump
	
viszero_leftbracket:
	inc ecx
	jmp viszero_jump

viszero_rightbracket:
	sub ecx, 1
	je interpret_loop
	jmp viszero_jump

visntzero:
	xor ecx, ecx
	inc ecx
	movzx bx, byte ptr [esi + edi]
	cmp bx, 0
	jne visntzero_jump
	jmp interpret_loop

visntzero_jump:
	sub dword ptr [ebp+8], 2
	mov esi, dword ptr [ebp+8]
	mov bl, byte ptr [esi-2]
	cmp bl, 5Dh
	je visntzero_rightbracket
	cmp bl, 5Bh
	je visntzero_leftbracket
	jmp visntzero_jump

visntzero_leftbracket:
	sub ecx, 1
	je interpret_loop
	jmp visntzero_jump

visntzero_rightbracket:
	inc ecx
	jmp visntzero_jump

; ############################ TO FIX

interpret_good_exit:				; 0
	xor eax, eax
	jmp interpret_free_and_exit

interpret_failed_to_alloc_mem:		; 1
	xor eax, eax
	inc eax
	jmp interpret_exit

interpret_out_of_bound:				; 2
	xor eax, eax
	inc eax
	inc eax
	jmp interpret_free_and_exit

interpret_invalid_instruction:		; 3
	mov eax, 3
	jmp interpret_free_and_exit

interpret_free_and_exit:
	push eax
	invoke crt_free, dword ptr [ebp-4]
	pop eax
interpret_exit:
	; epilogue
	add esp, 8
	mov esp, ebp
	pop ebp
	ret
interpret ENDP



main PROC
	; ebp-4  : allocated memory
	; ebp-8  : argc
	; ebp-12 : pointer to the input

	; prologue
	push ebp
	mov ebp, esp
	sub esp, 12

	invoke GetCommandLineW
	lea ebx, dword ptr [ebp-8]
	invoke CommandLineToArgvW, eax, ebx
	sub dword ptr [ebx], 3
	jnz main_incorrect_arguments

	;
	; The program has three entry mode
	; -d : debug mode
	; -f : interpret from file mode
	; -r : raw input mode
	;
	; implement a function to know what mode this is
	; right now, it assumes that every input is in -r mode
	;
	
	push dword ptr [eax+8]
	call interpret

	test eax, eax
	je main_success
	sub eax, 1
	je main_failed_to_alloc_mem
	sub eax, 1
	je main_out_of_bound
	sub eax, 1
	je main_invalid_instruction
	jmp main_unknown_error

main_success:
	invoke crt_puts, addr OperationEndedSuccessfully
	jmp main_exit

main_incorrect_arguments:
	invoke crt_puts, addr IncorrectArgumentsErrorMsg
	jmp main_exit

main_failed_to_alloc_mem:
	invoke crt_puts, addr FailedToAllocMemory
	jmp main_exit

main_out_of_bound:
	invoke crt_puts, addr OutOfBound
	jmp main_exit

main_invalid_instruction:
	invoke crt_puts, addr InvalidInstruction
	jmp main_exit

main_unknown_error:
	invoke crt_puts, addr UnknownError
	jmp main_exit
	
main_exit:
	; epilogue
	add esp, 12
	mov esp, ebp
	pop ebp
	ret
main ENDP

END
