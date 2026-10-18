-- Callers use multiples of 64 bytes. Offset tags make skipped or repeated
-- blocks distinguishable in the received payload.
return function(size)
    local blocks = {}
    for offset = 0, size - 1, 64 do
        blocks[#blocks + 1] = string.format('%064x', offset)
    end
    return table.concat(blocks)
end
