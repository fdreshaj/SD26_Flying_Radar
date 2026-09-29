# -*- coding: utf-8 -*-

# This example tests the throughput of the IQ acquisition mode
# of the receiver. Adjust the DECIMATION parameter to decimate
# the IQ data stream. DECIMATION must be a power of two.
# You should see samples rates of 50 MS/sec / DECIMATION
# for a USB device and up to 100 MS/s for a networked device

from smdevice.sm_api import *
import datetime

IS_NETWORKED = False # True for SM200C

SAMPLES_PER_CAPTURE = 262144
NUM_CAPTURES = 1000
DECIMATION = 1
BANDWIDTH = (160.0e6 if IS_NETWORKED else 20.0e6) / DECIMATION

def stream_iq():
    # Open device
    handle = -1
    if IS_NETWORKED:
        handle = sm_open_networked_device(SM200_ADDR_ANY, SM200_DEFAULT_ADDR, SM200_DEFAULT_PORT)["device"]
    else:
        handle = sm_open_device()["device"]

    # Configure device
    sm_set_IQ_center_freq(handle, 2e9)
    sm_set_IQ_sample_rate(handle, DECIMATION)
    sm_set_IQ_bandwidth(handle, SM_FALSE, BANDWIDTH)

    # Initialize
    sm_configure(handle, SM_MODE_IQ)

    # Stream IQ
    print ("Streaming...")
    sample_count = 0
    start_time = datetime.datetime.now()
    for i in range(NUM_CAPTURES):
        iq_buf = sm_get_IQ(handle, SAMPLES_PER_CAPTURE, 0, SM_FALSE)["iq_buf"]
        sample_count += SAMPLES_PER_CAPTURE

    # Print stats
    time_diff = (datetime.datetime.now() - start_time).total_seconds()
    print (f"\nCaptured {sample_count} samples @ {sample_count / time_diff / 1e6} megasamples/sec")

    # Close device
    sm_close_device(handle)


if __name__ == "__main__":
    stream_iq()
