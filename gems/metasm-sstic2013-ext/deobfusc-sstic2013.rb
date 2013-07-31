module Deobfuscate
  Patterns = {
    'mov r(\d), (\h+h?) ; jmp r\1' => 'jmp %2',
    'mov accu, 0 ; mov r(\d), accu ; mov r(\d), accu' => 'mov r%1, 0 ; mov r%2, 0',
    'mov accu, (\h+h?) ; mov r(\d), accu' => lambda { |dasm, list|
      # kludge
      list.last.address != 0x72 ? 'mov r%2, %1' : nil
    },
    'mov accu, 0 ; jmpz r(\d)' => 'jmp r%1',
    'mov accu, (\h+h?) ; msb accu' => lambda { |dasm, list|
      value = list.first.instruction.args[1]
      p = (1 << 7) | value.reduce
      "mov accu, #{p}"
    },
    'mov accu, r(\d) ; shl accu ; mov r\1, accu' => 'shl r%1',
    'mov accu, r(\d) ; mov r(\d), accu' => 'mov r%2, r%1',
    'mov accu, r(\d) ; or accu, r(\d) ; mov r\1, accu' => 'or r%1, r%2',
    'mov accu, r(\d) ; or accu, r(\d) ; mov r\2, accu' => 'or r%2, r%1',
  }
end

path = File.join(Metasm::Metasmdir, 'samples', 'dasm-plugins', 'deobfuscate.rb')
eval(File.read(path))
