# Makefile for CUDA hooking library

CC = gcc
CFLAGS = -Wall -fPIC -O2
LDFLAGS = -shared -ldl -lpthread

TARGET = libcuda_hook.so
SOURCE = cuda_hook.c

all: $(TARGET)

$(TARGET): $(SOURCE)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $(TARGET) $(SOURCE)
	@echo "Built $(TARGET) successfully"
	@echo ""
	@echo "Usage:"
	@echo "  LD_PRELOAD=./$(TARGET) python your_program.py"
	@echo "  LD_PRELOAD=./$(TARGET) CUDA_HOOK_TRACE=trace.jsonl ./your_cuda_app"

clean:
	rm -f $(TARGET)

test: $(TARGET)
	@echo "To test, run:"
	@echo "  LD_PRELOAD=./$(TARGET) python -c 'import torch; torch.cuda.is_available()'"

.PHONY: all clean test
