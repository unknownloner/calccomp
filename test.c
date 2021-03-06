void main() {
    clearScreen();
    putNum(8 - (3 + 2));
    putNum(2 + 2);
    getKey();
}

void clearScreen() {
asm {
    b_call(_ClrLCDFull)
    xor a
    ld (curRow), a
    ld (curCol), a
}
}

void putNum() {
asm {
    b_call(_DispHL)
    b_call(_NewLine)
}
}

void getKey() {
asm {
    b_call(_GetKey)
}
}
