# -*- coding: utf-8 -*-

# SM200B only.
# This example demonstrates setting up a single external triggered I/Q capture
# using the 160MHz I/Q capture capabilities of the SM200B.

from smdevice.sm_api import *

def iq_seg():
    # Number of I/Q samples
    PRETRIGGER_LEN = 16384
    POSTTRIGGER_LEN = 16384
    CAPTURE_LEN = PRETRIGGER_LEN + POSTTRIGGER_LEN

    handle = sm_open_device()["device"]

    sm_set_ref_level(handle, 0.0)

    sm_set_IQ_data_type(handle, SM_DATA_TYPE_32_FC)
    sm_set_IQ_center_freq(handle, 2e9)
    # Setup an rising edge external trigger
    sm_set_seg_IQ_ext_trigger(handle, SM_TRIGGER_EDGE_RISING)
    # Setup a single segment capture where the external trigger position
    # is at 50% (equal number of samples before and after the trigger)
    # 2 second timeout period.
    sm_set_seg_IQ_segment_count(handle, 1)
    sm_set_seg_IQ_segment(handle, 0, SM_TRIGGER_TYPE_EXT, PRETRIGGER_LEN, POSTTRIGGER_LEN, 2.0)

    sm_configure(handle, SM_MODE_IQ_SEGMENTED_CAPTURE)

    # Start the measurement, the SM200B will begin looking for an external
    #   trigger at this point.
    sm_seg_IQ_capture_start(handle, 0)

    # Notify some other device to transmit/trigger if necessary.

    # Block until complete
    sm_seg_IQ_capture_wait(handle, 0)
    # Did the capture timeout?
    timed_out = sm_seg_IQ_capture_timeout(handle, 0, 0)["timed_out"]
    # Read the timestamp
    ns_since_epoch = sm_seg_IQ_capture_time(handle, 0, 0)["ns_since_epoch"]
    # Read the I/Q data
    iq = sm_seg_IQ_capture_read(handle, 0, 0, 0, CAPTURE_LEN)["iq"]
    # Complete the transfer
    sm_seg_IQ_capture_finish(handle, 0)

    sm_abort(handle)
    sm_close_device(handle)

if __name__ == "__main__":
    iq_seg()
