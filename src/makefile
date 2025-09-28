ASM = nasm
ASM = nasm
ASMFLAGS = -f bin -l $(basename $<).lst
TARGET = itsy.com
SRC = itsy.asm

all: $(TARGET)

$(TARGET): $(SRC)
	$(ASM) $(ASMFLAGS) -o $@ $<
    
clean:
	rm -f $(TARGET) *.lst

