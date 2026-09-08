const GAME_ID = 1;
const MAX_RAM = 20;
const MAX_MEM_BYTES = 80;

contract RiscV {
    storage: Storage
}

struct Storage {
    gameId: int32
    pc: uint256
    halted: int32
    regs_1_4: uint256
    regs_5_8: uint256
    regsCell: cell
    ram: cell
    dataMem: cell
}

struct StateReply {
    gameId: int32
    pc: uint256
    halted: int32
    regs_1_4: uint256
    regs_5_8: uint256
    regsCell: cell
}

fun Storage.load(): Storage {
    var ds = contract.getData().beginParse();
    
    if (ds.remainingBitsCount() < 32 || ds.remainingRefsCount() < 3) {
        return Storage {
            gameId: GAME_ID,
            pc: 0,
            halted: 0,
            regs_1_4: 0,
            regs_5_8: 0,
            regsCell: beginCell().endCell(),
            ram: beginCell().endCell(),
            dataMem: beginCell().endCell()
        };
    }
    
    return Storage {
        gameId: ds.loadInt(32),
        pc: ds.loadUint(256),
        halted: ds.loadInt(32),
        regs_1_4: ds.loadUint(256),
        regs_5_8: ds.loadUint(256),
        regsCell: ds.loadRef(),
        ram: ds.loadRef(),
        dataMem: ds.loadRef()
    };
}

fun Storage.save(self) {
    contract.setData(
        beginCell()
        .storeInt(self.gameId, 32)
        .storeUint(self.pc, 256)
        .storeInt(self.halted, 32)
        .storeUint(self.regs_1_4, 256)
        .storeUint(self.regs_5_8, 256)
        .storeRef(self.regsCell)
        .storeRef(self.ram)
        .storeRef(self.dataMem)
        .endCell()
    );
}

// === Быстрые регистры x1-x8 ===
fun getR1(s: Storage): int { return (s.regs_1_4 & (0xFFFFFFFF << 224)) >> 224; }
fun getR2(s: Storage): int { return (s.regs_1_4 & (0xFFFFFFFF << 192)) >> 192; }
fun getR3(s: Storage): int { return (s.regs_1_4 & (0xFFFFFFFF << 160)) >> 160; }
fun getR4(s: Storage): int { return (s.regs_1_4 & (0xFFFFFFFF << 128)) >> 128; }
fun getR5(s: Storage): int { return (s.regs_5_8 & (0xFFFFFFFF << 224)) >> 224; }
fun getR6(s: Storage): int { return (s.regs_5_8 & (0xFFFFFFFF << 192)) >> 192; }
fun getR7(s: Storage): int { return (s.regs_5_8 & (0xFFFFFFFF << 160)) >> 160; }
fun getR8(s: Storage): int { return (s.regs_5_8 & (0xFFFFFFFF << 128)) >> 128; }

fun setR1(mutate s: Storage, value: int) {
    var lower = s.regs_1_4 & ~(0xFFFFFFFF << 224);
    s.regs_1_4 = lower | ((value & 0xFFFFFFFF) << 224);
}
fun setR2(mutate s: Storage, value: int) {
    var lower = s.regs_1_4 & ~(0xFFFFFFFF << 192);
    s.regs_1_4 = lower | ((value & 0xFFFFFFFF) << 192);
}
fun setR3(mutate s: Storage, value: int) {
    var lower = s.regs_1_4 & ~(0xFFFFFFFF << 160);
    s.regs_1_4 = lower | ((value & 0xFFFFFFFF) << 160);
}
fun setR4(mutate s: Storage, value: int) {
    var lower = s.regs_1_4 & ~(0xFFFFFFFF << 128);
    s.regs_1_4 = lower | ((value & 0xFFFFFFFF) << 128);
}
fun setR5(mutate s: Storage, value: int) {
    var lower = s.regs_5_8 & ~(0xFFFFFFFF << 224);
    s.regs_5_8 = lower | ((value & 0xFFFFFFFF) << 224);
}
fun setR6(mutate s: Storage, value: int) {
    var lower = s.regs_5_8 & ~(0xFFFFFFFF << 192);
    s.regs_5_8 = lower | ((value & 0xFFFFFFFF) << 192);
}
fun setR7(mutate s: Storage, value: int) {
    var lower = s.regs_5_8 & ~(0xFFFFFFFF << 160);
    s.regs_5_8 = lower | ((value & 0xFFFFFFFF) << 160);
}
fun setR8(mutate s: Storage, value: int) {
    var lower = s.regs_5_8 & ~(0xFFFFFFFF << 128);
    s.regs_5_8 = lower | ((value & 0xFFFFFFFF) << 128);
}

// === Медленные регистры x9-x31 ===
fun readRegCell(regsCell: cell, reg: int): int {
    if (reg < 9 || reg > 31) { return 0; }
    
    var s = regsCell.beginParse();
    var index = reg - 9;
    if (s.remainingBitsCount() < (index + 1) * 32) { return 0; }
    
    s.skipBits(index * 32);
    return s.loadUint(32);
}

fun writeRegCellRec(mutate b: builder, mutate existing: slice, i: int, reg: int, value: int): cell {
    if (i >= 23) {
        return b.endCell();
    }
    
    var regValue = 0;
    if (existing.remainingBitsCount() >= 32) {
        regValue = existing.loadUint(32);
    }
    
    var actualReg = i + 9;
    if (actualReg == reg) {
        b = b.storeUint(value & 0xFFFFFFFF, 32);
    } else {
        b = b.storeUint(regValue, 32);
    }
    
    return writeRegCellRec(mutate b, mutate existing, i + 1, reg, value);
}

fun writeRegCell(regsCell: cell, reg: int, value: int): cell {
    if (reg < 9 || reg > 31) { return regsCell; }
    
    var builder = beginCell();
    var existingSlice = regsCell.beginParse();
    return writeRegCellRec(mutate builder, mutate existingSlice, 0, reg, value);
}

fun readReg(s: Storage, reg: int): int {
    if (reg == 0) { return 0; }
    if (reg == 1) { return getR1(s); }
    if (reg == 2) { return getR2(s); }
    if (reg == 3) { return getR3(s); }
    if (reg == 4) { return getR4(s); }
    if (reg == 5) { return getR5(s); }
    if (reg == 6) { return getR6(s); }
    if (reg == 7) { return getR7(s); }
    if (reg == 8) { return getR8(s); }
    if (reg >= 9) { return readRegCell(s.regsCell, reg); }
    return 0;
}

fun writeReg(mutate s: Storage, reg: int, value: int) {
    if (reg == 0) { return; }
    if (reg == 1) { setR1(mutate s, value); }
    else if (reg == 2) { setR2(mutate s, value); }
    else if (reg == 3) { setR3(mutate s, value); }
    else if (reg == 4) { setR4(mutate s, value); }
    else if (reg == 5) { setR5(mutate s, value); }
    else if (reg == 6) { setR6(mutate s, value); }
    else if (reg == 7) { setR7(mutate s, value); }
    else if (reg == 8) { setR8(mutate s, value); }
    else if (reg >= 9) { s.regsCell = writeRegCell(s.regsCell, reg, value); }
}

fun toSigned32(v: int): int {
    if ((v & 0x80000000) != 0) { return v - 0x100000000; }
    return v;
}

// === Декодирование ===
fun decodeBranchImm(inst: int): int {
    var imm = 0;
    imm = imm | (((inst >> 31) & 1) << 12);
    imm = imm | (((inst >> 7) & 1) << 11);
    imm = imm | (((inst >> 25) & 0x3F) << 5);
    imm = imm | (((inst >> 8) & 0xF) << 1);
    if ((imm & 0x1000) != 0) { imm = imm - 0x2000; }
    return imm;
}

fun decodeJalImm(inst: int): int {
    var imm = 0;
    imm = imm | (((inst >> 31) & 1) << 20);
    imm = imm | (((inst >> 12) & 0xFF) << 12);
    imm = imm | (((inst >> 20) & 1) << 11);
    imm = imm | (((inst >> 21) & 0x3FF) << 1);
    if ((imm & 0x100000) != 0) { imm = imm - 0x200000; }
    return imm;
}

fun decodeStoreImm(inst: int): int {
    var imm = 0;
    imm = imm | (((inst >> 25) & 0x7F) << 5);
    imm = imm | ((inst >> 7) & 0x1F);
    if ((imm & 0x800) != 0) { imm = imm - 0x1000; }
    return imm;
}

// === Память ===
fun ramRead(ram: cell, address: int): int {
    var wordIndex = address / 4;
    if (wordIndex >= MAX_RAM) { return 0; }
    
    var s = ram.beginParse();
    if (s.remainingBitsCount() < 32) { return 0; }
    if (s.remainingBitsCount() < (wordIndex + 1) * 32) { return 0; }
    
    s.skipBits(wordIndex * 32);
    return s.loadUint(32);
}

fun readMemByte(mem: cell, address: int): int {
    if (address < 0 || address >= MAX_MEM_BYTES) { return 0; }
    
    var s = mem.beginParse();
    if (s.remainingBitsCount() < (address + 1) * 8) { return 0; }
    
    s.skipBits(address * 8);
    return s.loadUint(8);
}

fun readMemHalf(mem: cell, address: int): int {
    var byte0 = readMemByte(mem, address);
    var byte1 = readMemByte(mem, address + 1);
    return byte0 | (byte1 << 8);
}

fun readMemWord(mem: cell, address: int): int {
    var byte0 = readMemByte(mem, address);
    var byte1 = readMemByte(mem, address + 1);
    var byte2 = readMemByte(mem, address + 2);
    var byte3 = readMemByte(mem, address + 3);
    return byte0 | (byte1 << 8) | (byte2 << 16) | (byte3 << 24);
}

fun writeMemByteRec(mutate b: builder, mutate existing: slice, i: int, address: int, value: int): cell {
    if (i >= MAX_MEM_BYTES) {
        return b.endCell();
    }
    
    var byteValue = 0;
    if (existing.remainingBitsCount() >= 8) {
        byteValue = existing.loadUint(8);
    }
    
    if (i == address) {
        b = b.storeUint(value & 0xFF, 8);
    } else {
        b = b.storeUint(byteValue, 8);
    }
    
    return writeMemByteRec(mutate b, mutate existing, i + 1, address, value);
}

fun writeMemByte(mem: cell, address: int, value: int): cell {
    if (address < 0 || address >= MAX_MEM_BYTES) { return mem; }
    
    var builder = beginCell();
    var existingSlice = mem.beginParse();
    return writeMemByteRec(mutate builder, mutate existingSlice, 0, address, value);
}

fun writeMemHalf(mem: cell, address: int, value: int): cell {
    mem = writeMemByte(mem, address, value & 0xFF);
    mem = writeMemByte(mem, address + 1, (value >> 8) & 0xFF);
    return mem;
}

fun writeMemWord(mem: cell, address: int, value: int): cell {
    mem = writeMemByte(mem, address, value & 0xFF);
    mem = writeMemByte(mem, address + 1, (value >> 8) & 0xFF);
    mem = writeMemByte(mem, address + 2, (value >> 16) & 0xFF);
    mem = writeMemByte(mem, address + 3, (value >> 24) & 0xFF);
    return mem;
}

// === Загрузка программы ===
fun loadProgramRec(mutate s: slice, mutate b: builder, count: int): cell {
    if (count >= MAX_RAM || s.isEndOfBits()) {
        return b.endCell();
    }
    
    var inst = readHex32(mutate s);
    b = b.storeUint(inst & 0xFFFFFFFF, 32);
    
    if (!s.isEndOfBits()) {
        var nextByte = s.preloadUint(8);
        if (nextByte == 44) {
            s.loadUint(8);
        }
    }
    
    return loadProgramRec(mutate s, mutate b, count + 1);
}

// === Выполнение ===
fun executeOne(mutate s: Storage): void {
    if (s.halted != 0) { return; }
    
    var inst = ramRead(s.ram, s.pc);
    if (inst == 0) {
        s.halted = 1;
        return;
    }
    
    var opcode = inst & 0x7F;
    var rd = (inst >> 7) & 0x1F;
    var funct3 = (inst >> 12) & 0x7;
    var rs1 = (inst >> 15) & 0x1F;
    var rs2 = (inst >> 20) & 0x1F;
    var funct7 = (inst >> 25) & 0x7F;
    
    var src1 = readReg(s, rs1);
    var src2 = readReg(s, rs2);
    
    var nextPc = s.pc + 4;
    
    // R-Type
    if (opcode == 0x33) {
        if (funct7 == 0x00 && funct3 == 0x0) { writeReg(mutate s, rd, src1 + src2); }
        else if (funct7 == 0x20 && funct3 == 0x0) { writeReg(mutate s, rd, src1 - src2); }
        else if (funct7 == 0x00 && funct3 == 0x1) { writeReg(mutate s, rd, src1 << (src2 & 0x1F)); }
        else if (funct7 == 0x00 && funct3 == 0x2) {
            var signed1 = toSigned32(src1);
            var signed2 = toSigned32(src2);
            if (signed1 < signed2) { writeReg(mutate s, rd, 1); }
            else { writeReg(mutate s, rd, 0); }
        }
        else if (funct7 == 0x00 && funct3 == 0x3) {
            if ((src1 & 0xFFFFFFFF) < (src2 & 0xFFFFFFFF)) { writeReg(mutate s, rd, 1); }
            else { writeReg(mutate s, rd, 0); }
        }
        else if (funct7 == 0x00 && funct3 == 0x4) { writeReg(mutate s, rd, src1 ^ src2); }
        else if (funct7 == 0x00 && funct3 == 0x5) { writeReg(mutate s, rd, src1 >> (src2 & 0x1F)); }
        else if (funct7 == 0x20 && funct3 == 0x5) {
            var signedVal = toSigned32(src1);
            writeReg(mutate s, rd, signedVal >> (src2 & 0x1F));
        }
        else if (funct7 == 0x00 && funct3 == 0x6) { writeReg(mutate s, rd, src1 | src2); }
        else if (funct7 == 0x00 && funct3 == 0x7) { writeReg(mutate s, rd, src1 & src2); }
        else { s.halted = 1; return; }
        s.pc = nextPc;
    }
    // I-Type
    else if (opcode == 0x13) {
        var imm = (inst >> 20) & 0xFFF;
        if ((imm & 0x800) != 0) { imm = imm - 0x1000; }
        
        if (funct3 == 0x0) { writeReg(mutate s, rd, src1 + imm); }
        else if (funct3 == 0x2) {
            var signed1 = toSigned32(src1);
            if (signed1 < imm) { writeReg(mutate s, rd, 1); }
            else { writeReg(mutate s, rd, 0); }
        }
        else if (funct3 == 0x3) {
            if ((src1 & 0xFFFFFFFF) < (imm & 0xFFFFFFFF)) { writeReg(mutate s, rd, 1); }
            else { writeReg(mutate s, rd, 0); }
        }
        else if (funct3 == 0x4) { writeReg(mutate s, rd, src1 ^ imm); }
        else if (funct3 == 0x6) { writeReg(mutate s, rd, src1 | imm); }
        else if (funct3 == 0x7) { writeReg(mutate s, rd, src1 & imm); }
        else if (funct3 == 0x1) { writeReg(mutate s, rd, src1 << (imm & 0x1F)); }
        else if (funct3 == 0x5 && funct7 == 0x00) { writeReg(mutate s, rd, src1 >> (imm & 0x1F)); }
        else if (funct3 == 0x5 && funct7 == 0x20) {
            var signedVal = toSigned32(src1);
            writeReg(mutate s, rd, signedVal >> (imm & 0x1F));
        }
        else { s.halted = 1; return; }
        s.pc = nextPc;
    }
    // Load
    else if (opcode == 0x03) {
        var imm = (inst >> 20) & 0xFFF;
        if ((imm & 0x800) != 0) { imm = imm - 0x1000; }
        var addr = src1 + imm;
        
        if (funct3 == 0x0) {
            var byteVal = readMemByte(s.dataMem, addr);
            if ((byteVal & 0x80) != 0) { byteVal = byteVal - 0x100; }
            writeReg(mutate s, rd, byteVal);
        }
        else if (funct3 == 0x1) {
            var halfVal = readMemHalf(s.dataMem, addr);
            if ((halfVal & 0x8000) != 0) { halfVal = halfVal - 0x10000; }
            writeReg(mutate s, rd, halfVal);
        }
        else if (funct3 == 0x2) { writeReg(mutate s, rd, readMemWord(s.dataMem, addr)); }
        else if (funct3 == 0x4) { writeReg(mutate s, rd, readMemByte(s.dataMem, addr)); }
        else if (funct3 == 0x5) { writeReg(mutate s, rd, readMemHalf(s.dataMem, addr)); }
        else { s.halted = 1; return; }
        s.pc = nextPc;
    }
    // Store
    else if (opcode == 0x23) {
        var imm = decodeStoreImm(inst);
        var addr = src1 + imm;
        
        if (funct3 == 0x0) { s.dataMem = writeMemByte(s.dataMem, addr, src2 & 0xFF); }
        else if (funct3 == 0x1) { s.dataMem = writeMemHalf(s.dataMem, addr, src2); }
        else if (funct3 == 0x2) { s.dataMem = writeMemWord(s.dataMem, addr, src2); }
        else { s.halted = 1; return; }
        s.pc = nextPc;
    }
    // Branch
    else if (opcode == 0x63) {
        var imm13 = decodeBranchImm(inst);
        if (funct3 == 0x0) {
            if (src1 == src2) { s.pc = s.pc + imm13; } else { s.pc = nextPc; }
        }
        else if (funct3 == 0x1) {
            if (src1 != src2) { s.pc = s.pc + imm13; } else { s.pc = nextPc; }
        }
        else if (funct3 == 0x4) {
            var signed1 = toSigned32(src1);
            var signed2 = toSigned32(src2);
            if (signed1 < signed2) { s.pc = s.pc + imm13; } else { s.pc = nextPc; }
        }
        else if (funct3 == 0x5) {
            var signed1 = toSigned32(src1);
            var signed2 = toSigned32(src2);
            if (signed1 >= signed2) { s.pc = s.pc + imm13; } else { s.pc = nextPc; }
        }
        else { s.halted = 1; return; }
    }
    // JAL
    else if (opcode == 0x6F) {
        var imm21 = decodeJalImm(inst);
        if (rd != 0) { writeReg(mutate s, rd, s.pc + 4); }
        s.pc = s.pc + imm21;
    }
    // JALR
    else if (opcode == 0x67) {
        var imm = (inst >> 20) & 0xFFF;
        if ((imm & 0x800) != 0) { imm = imm - 0x1000; }
        var target = (src1 + imm) & ~1;
        if (rd != 0) { writeReg(mutate s, rd, s.pc + 4); }
        s.pc = target;
    }
    // LUI
    else if (opcode == 0x37) {
        writeReg(mutate s, rd, inst & 0xFFFFF000);
        s.pc = nextPc;
    }
    // AUIPC
    else if (opcode == 0x17) {
        writeReg(mutate s, rd, s.pc + (inst & 0xFFFFF000));
        s.pc = nextPc;
    }
    // ECALL
    else if (opcode == 0x73) {
        s.halted = 1;
    }
    else {
        s.halted = 1;
    }
}

// === Hex-вывод ===
fun printHex(mutate b: builder, value: int, count: int): void {
    if (count >= 8) { return; }
    
    var shift = 28 - count * 4;
    var digit = (value >> shift) & 0xF;
    
    if (digit < 10) {
        b = b.storeUint(48 + digit, 8);
    } else {
        b = b.storeUint(97 + digit - 10, 8);
    }
    
    printHex(mutate b, value, count + 1);
}

// === Обработка сообщений ===
fun onInternalMessage(in: InMessage) {
    var storage = Storage.load();
    
    var b = beginCell().storeUint(0, 32);
    
    if (!in.body.isEmpty()) {
        var commandSlice = in.body;
        var prefix = commandSlice.preloadUint(32);
        if (prefix == 0) {
            commandSlice.loadUint(32);
        }
        
        if (!commandSlice.isEndOfBits()) {
            var cmd = commandSlice.loadUint(8);
            
            if (cmd == 0x72) { // 'r'
                if (ramRead(storage.ram, storage.pc) == 0) {
                    storage.halted = 1;
                } else {
                    storage.halted = 0;
                }
                repeat (100) {
                    if (storage.halted == 0) {
                        executeOne(mutate storage);
                    }
                }
                storage.save();
                b = b.storeUint(82, 8).storeUint(85, 8).storeUint(78, 8);
                b = b.storeUint(32, 8);
                b = b.storeUint(48 + (storage.pc / 100) % 10, 8);
                b = b.storeUint(48 + (storage.pc / 10) % 10, 8);
                b = b.storeUint(48 + storage.pc % 10, 8);
            } else if (cmd == 0x73) { // 's'
                if (ramRead(storage.ram, storage.pc) == 0) {
                    storage.halted = 1;
                } else {
                    storage.halted = 0;
                }
                executeOne(mutate storage);
                storage.save();
                b = b.storeUint(83, 8).storeUint(58, 8).storeUint(32, 8);
                b = b.storeUint(48 + (storage.pc / 100) % 10, 8);
                b = b.storeUint(48 + (storage.pc / 10) % 10, 8);
                b = b.storeUint(48 + storage.pc % 10, 8);
            } else if (cmd == 0x6C) { // 'l'
                var builder = beginCell();
                storage.ram = loadProgramRec(mutate commandSlice, mutate builder, 0);
                storage.pc = 0;
                storage.halted = 0;
                storage.save();
                b = b.storeUint(76, 8).storeUint(68, 8);
            } else if (cmd == 0x68) { // 'h' — x1 (hex)
                var x1 = getR1(storage);
                b = b.storeUint(88, 8).storeUint(49, 8).storeUint(61, 8);
                printHex(mutate b, x1 & 0xFFFFFFFF, 0);
            } else if (cmd == 0x67) { // 'g' — x2 (hex)
                var x2 = getR2(storage);
                b = b.storeUint(88, 8).storeUint(50, 8).storeUint(61, 8);
                printHex(mutate b, x2 & 0xFFFFFFFF, 0);
            } else if (cmd == 0x33) { // '3' — x3 (hex)
                var x3 = getR3(storage);
                b = b.storeUint(88, 8).storeUint(51, 8).storeUint(61, 8);
                printHex(mutate b, x3 & 0xFFFFFFFF, 0);
            } else if (cmd == 0x35) { // '5' — x5 (hex)
                var x5 = getR5(storage);
                b = b.storeUint(88, 8).storeUint(53, 8).storeUint(61, 8);
                printHex(mutate b, x5 & 0xFFFFFFFF, 0);
            } else if (cmd == 0x6D) { // 'm'
                var memValue = ramRead(storage.ram, storage.pc);
                b = b.storeUint(77, 8).storeUint(61, 8);
                printHex(mutate b, memValue & 0xFFFFFFFF, 0);
            }
        }
    } else {
        storage.save();
        b = b.storeUint(79, 8).storeUint(75, 8);
    }
    
    val reply = createMessage({
        bounce: BounceMode.NoBounce,
        dest: in.senderAddress,
        value: 0,
        body: b.endCell()
    });
    reply.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
}

fun readHex32(mutate s: slice): int {
    var result = 0;
    
    repeat (8) {
        if (s.isEndOfBits()) { return result; }
        
        var byte = s.preloadUint(8);
        var digit = -1;
        
        if (byte >= 48 && byte <= 57) {
            digit = byte - 48;
        } else if (byte >= 97 && byte <= 102) {
            digit = byte - 97 + 10;
        } else if (byte >= 65 && byte <= 70) {
            digit = byte - 65 + 10;
        } else {
            return result;
        }
        
        s.loadUint(8);
        result = (result << 4) | digit;
    }
    return result;
}

get fun get_state(): StateReply {
    val s = Storage.load();
    return StateReply {
        gameId: s.gameId,
        pc: s.pc,
        halted: s.halted,
        regs_1_4: s.regs_1_4,
        regs_5_8: s.regs_5_8,
        regsCell: s.regsCell
    };
}
