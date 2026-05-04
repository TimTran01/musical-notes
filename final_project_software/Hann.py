import numpy as np

def generate_vhdl_hann_half_rom(N=4096, bits=24):
    half_N = N // 2
    n = np.arange(half_N)

    # Hann window
    window = 0.5 * (1 - np.cos(2 * np.pi * n / (N - 1)))

    # Convert to signed [-1, +1]
    max_val = (1 << (bits - 1)) - 1
    signed = np.round((2 * window - 1) * max_val)

    signed = np.clip(signed, -max_val-1, max_val).astype(np.int32)

    print(f"-- Symmetric Signed Hann ROM (half size)")
    print(f"-- Full size: {N}, Stored: {half_N}")

    print("constant ROM : rom_type := (")

    for i in range(0, half_N, 8):
        chunk = signed[i:i+8]

        # convert signed → two’s complement hex
        hex_row = ", ".join(
            [f'x"{(val & ((1<<bits)-1)):0{bits//4}X}"' for val in chunk]
        )

        line_end = "," if i + 8 < half_N else ""
        print(f"    {hex_row}{line_end}")

    print(");")

generate_vhdl_hann_half_rom()