# -*- coding: utf-8 -*-

# This example configures the receiver for IQ acquisition and plots
# the spectrum of a single IQ acquisition.

from smdevice.sm_api import *

from scipy.signal import get_window
import matplotlib.pyplot as plt
import seaborn as sns; sns.set() # styling

def iq():
    # Open device
    serials = sm_get_device_list()
    print(serials)
    handle = sm_open_device()["device"]

    # Configure device
    sm_set_IQ_center_freq(handle, 2e9)
    sm_set_IQ_sample_rate(handle, 64)
    sm_set_IQ_bandwidth(handle, SM_TRUE, 10e6)

    # Initialize
    sm_configure(handle, SM_MODE_IQ)

    # Get IQ data
    iq_buf = sm_get_IQ(handle, 15625, 0, SM_TRUE)["iq_buf"]
    sample_rate = sm_get_IQ_parameters(handle)
    print(sample_rate)

    # No longer need device, close
    sm_close_device(handle)
    plt.plot(iq_buf)
    plt.show()
    # Now lets FFT and plot

    # Create window
    window = get_window('hamming', len(iq_buf))
    # Normalize window
    window *= len(window) / sum(window)
    # Window, FFT, normalize FFT output
    iq_data_FFT = numpy.fft.fftshift(numpy.fft.fft(iq_buf * window) / len(window))
    # Convert to dBm
    plt.plot(10 * numpy.log10(iq_data_FFT.real ** 2 + iq_data_FFT.imag ** 2))
    plt.show()

if __name__ == "__main__":
    iq()
