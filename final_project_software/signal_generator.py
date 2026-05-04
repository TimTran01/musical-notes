import numpy as np
import matplotlib.pyplot as plt
import math
from scipy.io import wavfile  # Standard way to save audio


def generate_string_note(freq, duration, sample_rate=44100, hammer_hardness=0.2):
    """
    hammer_hardness: 0.0 to 1.0. 
    0.1 is a soft felt hammer (muffled), 0.9 is a hard plastic strike (bright).
    """
    L = int(sample_rate / freq)
    
    # 1. Generate Raw White Noise Strike
    raw_noise = np.random.uniform(-1, 1, L)
    
    # 2. Add Low-Pass Filter to the Hammer Strike
    # Simple one-pole: y[n] = a*x[n] + (1-a)*y[n-1]
    filtered_buffer = np.zeros(L)
    prev_val = 0
    for i in range(L):
        # hammer_hardness acts as the filter coefficient
        filtered_buffer[i] = hammer_hardness * raw_noise[i] + (1 - hammer_hardness) * prev_val
        prev_val = filtered_buffer[i]
    
    # Use the filtered noise as our initial buffer
    buffer = filtered_buffer
    
    n_samples = int(sample_rate * duration)
    output = np.zeros(n_samples)
    
    # 3. Feedback Loop (Physical Model)
    for i in range(n_samples):
        output[i] = buffer[0]
        
        # Averaging filter + Decay
        # This part is ALSO a low-pass filter, making the note "darken" as it rings
        new_sample = 0.5 * (buffer[0] + buffer[1]) * 0.95
        
        # Circular buffer update
        buffer = np.append(buffer[1:], new_sample)
        
    return output

# Generate the note


def generate_piano_frequencies():
    # Number of keys on a standard piano
    num_keys = 88
    
    # Standard reference: The 49th key is A4, which is 440 Hz
    a4_index = 49
    a4_freq = 440.0
    
    # Use a numpy array for efficient math
    indices = np.arange(1, num_keys + 1)
    
    # The standard formula for equal temperament
    frequencies = a4_freq * (2 ** ((indices - a4_index) / 12.0))
    
    return frequencies


def simulate_24bit_adc(freq, samples=1024, fs=48000, noise_level=0.0001):
    """
    Simulates a 24-bit ADC sampling a piano note.
    Commonly 24-bit ADCs use 48kHz or 96kHz.
    """
        # Instead of: duration = 0.341
    #N = 1024  # Your fixed buffer size
    t = np.arange(samples) / fs
    #t = np.linspace(0, duration, int(fs * duration), False)
    
    # 1. Generate Signal (Complex Piano Wave)
    # Range -1.0 to 1.0
    signal = (1.0 * np.sin(2 * np.pi * freq * t) + 
              0.5 * np.sin(2 * np.pi * 2 * freq * t) + 
              0.25 * np.sin(2 * np.pi * 3 * freq * t))
    
    # Normalize to -0.9 to 0.9 to avoid clipping
    signal = (signal / np.max(np.abs(signal))) * 0.9
    
    # 2. Add realistic Noise (at 24-bit, noise is very subtle)
    noise = np.random.normal(0, noise_level, len(t))
    analog_signal = signal + noise
    
    # 3. 24-bit Quantization
    # Range: -8,388,608 to 8,388,607
    adc_max = 2**23 - 1
    adc_data = (analog_signal * adc_max).astype(np.int32)
    
    return t, adc_data


def generate_vhdl_coeffs():
    notes = ['A', 'A#', 'B', 'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#']
    
    print(f"{'Key':<4} | {'Note':<6} | {'Target Freq':<12} | {'Zone fs':<10} | {'Coeff (2*cos(w))':<18}")
    print("-" * 65)
    
    for n in range(1, 89):
        # 1. Frequency
        freq = 440.0 * (2 ** ((n - 49) / 12.0))
        
        # 2. Determine Zone and Sampling Rate
        if n <= 27:      # Zone 1: A0 to B2
            fs_zone = 3000
        elif n <= 63:    # Zone 2: C3 to D#6
            fs_zone = 12000
        else:            # Zone 3: E6 to C8
            fs_zone = 48000
            
        # 3. Calculate Coefficient
        # w = 2 * pi * k / N, but k = (f_target * N) / fs
        # Simplified: w = 2 * pi * f_target / fs
        omega = (2.0 * math.pi * freq) / fs_zone
        coeff = 2.0 * math.cos(omega)
        
        # Note Name
        name = notes[(n - 1) % 12] + str((n + 8) // 12)
        
        if n % 10 == 0 or n == 1 or n == 88: # Print selection to save space
            print(f"{n:<4} | {name:<6} | {freq:>10.2f} Hz | {fs_zone:>8} | {coeff:>18.14f}")


def goertzel(samples, target_freq, fs):

    # Apply a Hann Window to the samples first
    N = len(samples)
    window = np.hanning(N)
    samples = samples * window  # This smooths the edges

    # N = len(samples)
    # 1. Precompute constants
    k = (N * target_freq) / fs
    omega = (2.0 * math.pi * k) / N
    cosine = math.cos(omega)
    coeff = 2.0 * cosine

    # 2. Feedback loop (This part goes in your real-time C loop)
    s_prev = 0.0
    s_prev2 = 0.0
    
    for x in samples:
        s = x + (coeff * s_prev) - s_prev2
        s_prev2 = s_prev
        s_prev = s

    # 3. Magnitude calculation
    power = (s_prev2 * s_prev2) + (s_prev * s_prev) - (coeff * s_prev * s_prev2)
    return math.sqrt(power)

# --- 1. Generate Piano Frequency Table ---
def get_piano_frequencies():
    # A4 is the standard reference at 440Hz
    # It is the 49th key on a standard 88-key piano
    frequencies = {}
    note_names = ['A', 'A#', 'B', 'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#']
    
    for n in range(1, 89):
        # Frequency formula for the nth key
        freq = 440.0 * (2 ** ((n - 49) / 12.0))
        #print(freq)
        
        # Calculate note name and octave
        # Key 1 is A0, Key 4 is C1, etc.
        name = note_names[(n - 1) % 12]
        octave = (n + 8) // 12
        full_name = f"{name}{octave}"
        
        frequencies[full_name] = freq
    return frequencies

# --- 2. Enhanced Scanner ---
def scan_all_keys(samples, fs):
    piano_table = get_piano_frequencies()
    results = []

    print(f"{'Note':<10} | {'Freq (Hz)':<10} | {'Magnitude':<15}")
    print("-" * 40)

    for note, target_f in piano_table.items():
        mag = goertzel(samples, target_f, fs)
        results.append((note, target_f, mag))

    # Sort results by magnitude to find the strongest match
    results.sort(key=lambda x: x[2], reverse=True)
    
    return results


# Generate the array
piano_freqs = generate_piano_frequencies()

# print(piano_freqs)
# Print a few examples
# print(f"Key 1 (A0): {piano_freqs[0]:.2f} Hz")
# print(f"Key 40 (Middle C): {piano_freqs[39]:.2f} Hz")
# print(f"Key 49 (A4): {piano_freqs[48]:.2f} Hz")
# print(f"Key 88 (C8): {piano_freqs[87]:.2f} Hz")

# If you need this as a standard Python list for your loops:
freq_list = piano_freqs.tolist()

#print(freq_list)

# --- 3. Execution ---
# Generate our 440Hz (A4) sample again for testing
fs = 3000
t, adc_samples = simulate_24bit_adc(27.5, 4096, fs=fs)


# Assuming t and adc_samples are already defined from your simulation
# Example parameters used: f_in = 27.5, n_samples = 2048, fs = 1000

plt.figure(figsize=(10, 8))

# # --- Plot 1: Time Domain ---
# plt.subplot(2, 1, 1)
# # Plotting a subset of samples (e.g., first 200) to see the waveform clearly
# plt.plot(t[:200], adc_samples[:200], color='tab:blue', linewidth=1.5)
# plt.title("24-bit ADC Output (Time Domain - First 200 Samples)")
# plt.xlabel("Time (s)")
# plt.ylabel("ADC Counts (LSD)")
# plt.grid(True, linestyle='--', alpha=0.7)

# # --- Plot 2: Frequency Domain (FFT) ---
# plt.subplot(2, 1, 2)
# n = len(adc_samples)
# # Apply a Hann window to reduce spectral leakage
# window = np.hanning(len(adc_samples))
# fft_data = np.fft.rfft(adc_samples * window)

# # Compute FFT and normalize magnitude
# #fft_data = np.fft.rfft(adc_samples)
# freqs = np.fft.rfftfreq(n, 1/fs)
# # Convert to dBFS (Decibels relative to Full Scale)
# # Full scale for 24-bit is 2^23
# magnitude_db = 20 * np.log10(np.abs(fft_data) / (n/2 * (2**23)))

# plt.plot(freqs, magnitude_db, color='tab:red')
# plt.title("Power Spectrum (Frequency Domain)")
# plt.xlabel("Frequency (Hz)")
# plt.ylabel("Magnitude (dBFS)")
# plt.ylim([-200, 0]) # 24-bit theoretical floor is ~ -144dB
# plt.grid(True, linestyle='--', alpha=0.7)

# plt.tight_layout()
# plt.show()



note_audio = generate_string_note(27.5, 1, fs)

# Convert to 16-bit PCM (standard for .wav files)
# This is crucial for playback compatibility
# audio_fixed = (note_audio * 32767).astype(np.int16)
# wavfile.write("piano_note.wav", 44100, audio_fixed)
print("File saved as piano_note.wav")

all_results = scan_all_keys(adc_samples, fs)
# Display the Top 5 strongest detections
print("\nTop 5 Detected Notes:")
for i in range(5):
    note, freq, mag = all_results[i]
    db_scale = 20 * math.log10(mag)
    print(f"{i+1}. {note:<5} ({freq:>7.2f} Hz) -> Mag: {mag:,.0f} {db_scale} dB")