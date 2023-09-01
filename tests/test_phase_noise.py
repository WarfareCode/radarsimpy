"""
    A Python module for radar simulation

    ----------
    RadarSimPy - A Radar Simulator Built with Python
    Copyright (C) 2018 - PRESENT  Zhengyu Peng
    E-mail: zpeng.me@gmail.com
    Website: https://zpeng.me

    `                      `
    -:.                  -#:
    -//:.              -###:
    -////:.          -#####:
    -/:.://:.      -###++##:
    ..   `://:-  -###+. :##:
           `:/+####+.   :##:
    .::::::::/+###.     :##:
    .////-----+##:    `:###:
     `-//:.   :##:  `:###/.
       `-//:. :##:`:###/.
         `-//:+######/.
           `-/+####/.
             `+##+.
              :##:
              :##:
              :##:
              :##:
              :##:
               .+:

"""

from radarsimpy import Radar, Transmitter, Receiver
from radarsimpy.simulator import simc
from radarsimpy.simulator import simpy
from radarsimpy.util import cal_phase_noise
from scipy import signal
import radarsimpy.processing as proc
import numpy as np
import numpy.testing as npt


def test_phase_noise():
    sig = np.ones((1, 256))
    pn_f = np.array([1000, 10000, 100000, 1000000])
    pn_power_db_per_hz = np.array([-84, -100, -96, -109])
    fs = 4e6

    pn = cal_phase_noise(sig, fs, pn_f, pn_power_db_per_hz, validation=True)

    # f = np.linspace(0, fs, 256)
    spec = 20*np.log10(np.abs(np.fft.fft(pn[0, :]/256)))

    # pn_power_db = pn_power_db_per_hz+10*np.log10(fs/256)

    npt.assert_almost_equal(spec[1], -63.4, decimal=2)
    npt.assert_almost_equal(spec[6], -60.21, decimal=2)
    npt.assert_almost_equal(spec[64], -73.09, decimal=2)


def test_fmcw_phase_noise_cpp():
    tx_channel = dict(
        location=(0, 0, 0)
    )

    pn_f = np.array([1000, 10000, 100000, 1000000])
    pn_power = np.array([-65, -70, -65, -90])

    tx_pn = Transmitter(f=[24.125e9-50e6, 24.125e9+50e6],
                        t=80e-6,
                        tx_power=40,
                        prp=100e-6,
                        pulses=1,
                        pn_f=pn_f,
                        pn_power=pn_power,
                        channels=[tx_channel])

    tx = Transmitter(f=[24.125e9-50e6, 24.125e9+50e6],
                     t=80e-6,
                     tx_power=40,
                     prp=100e-6,
                     pulses=1,
                     channels=[tx_channel])

    rx_channel = dict(
        location=(0, 0, 0)
    )

    rx = Receiver(fs=2e6,
                  noise_figure=12,
                  rf_gain=20,
                  load_resistor=500,
                  baseband_gain=30,
                  channels=[rx_channel])

    radar_pn = Radar(transmitter=tx_pn, receiver=rx,
                     seed=1234, validation=True)
    radar = Radar(transmitter=tx, receiver=rx, seed=1234, validation=True)

    target_1 = dict(location=(150, 20, 0), speed=(0, 0, 0), rcs=60, phase=0)

    targets = [target_1]

    data_cpp_pn = simc(radar_pn, targets, noise=False)
    data_matrix_cpp_pn = data_cpp_pn['baseband']
    data_cpp = simc(radar, targets, noise=False)
    data_matrix_cpp = data_cpp['baseband']

    range_window = signal.windows.chebwin(radar.samples_per_pulse, at=60)
    range_profile_pn = proc.range_fft(data_matrix_cpp_pn, range_window)
    range_profile = proc.range_fft(data_matrix_cpp, range_window)

    range_profile_pn = 20 * \
        np.log10(np.abs(range_profile_pn[0, 0, :]))
    range_profile = 20 * \
        np.log10(np.abs(range_profile[0, 0, :]))

    profile_diff = range_profile_pn-range_profile

    npt.assert_allclose(
        profile_diff,
        np.array([
            8.79798637e+00, 8.92852677e+00, 9.10244790e+00, 9.23691427e+00,
            9.39637374e+00, 9.55030817e+00, 9.75201879e+00, 9.99391771e+00,
            1.02540629e+01, 1.05633725e+01, 1.09709745e+01, 1.14634761e+01,
            1.20602118e+01, 1.27221889e+01, 1.34656013e+01, 1.43745850e+01,
            1.53798577e+01, 1.65158326e+01, 1.76935265e+01, 1.90055719e+01,
            1.94698268e+01, 2.74742955e+01, 2.27652179e+01, 2.41057326e+01,
            2.51006053e+01, 2.64592428e+01, 2.80574979e+01, 3.02969827e+01,
            3.35404161e+01, 4.03730894e+01, 5.10139042e+01, 3.61690121e+01,
            3.05100242e+01, 2.68250805e+01, 2.38824627e+01, 2.14787115e+01,
            1.94539696e+01, 1.76038801e+01, 1.58218269e+01, 1.41671421e+01,
            1.25263458e+01, 1.09833725e+01, 9.36974652e+00, 7.78373012e+00,
            6.14752450e+00, 4.45653221e+00, 2.69558824e+00, 8.92489685e-01,
            -9.88604711e-01, -2.77310247e+00, -4.34194299e+00, -5.34248482e+00,
            -5.58878960e+00, -5.17162741e+00, -4.43632751e+00, -3.59143526e+00,
            -2.79504101e+00, -2.08075069e+00, -1.44908234e+00, -9.12383849e-01,
            -4.49804341e-01, -5.21983807e-02, 2.85803922e-01, 5.75951386e-01,
            8.28473424e-01, 1.04610451e+00, 1.24001324e+00, 1.41735362e+00,
            1.58596369e+00, 1.74589347e+00, 1.91689014e+00, 2.07782510e+00,
            2.28588639e+00, 2.49213422e+00, 2.72855815e+00, 3.00658524e+00,
            3.31348973e+00, 3.67142504e+00, 4.04902702e+00, 4.50009494e+00,
            4.97741334e+00, 5.50357818e+00, 6.07309727e+00, 6.73237712e+00,
            7.41145104e+00, 8.18894268e+00, 9.01696097e+00, 1.00455593e+01,
            1.11374080e+01, 1.25478502e+01, 1.42728844e+01, 1.66367794e+01,
            2.05593639e+01, 2.74899059e+01, 3.13456951e+01, 2.00634893e+01,
            1.50121223e+01, 1.21829281e+01, 1.69154068e+01, -5.77896226e-01,
            4.88479938e-02, -2.41179037e-02, 4.39818875e-02, -7.01442870e-01,
            1.22746498e+01, 1.25900205e+01, 1.88463218e+01, 5.52312297e+01,
            2.00740761e+01, 1.58423063e+01, 1.25294146e+01, 1.08581000e+01,
            9.58197592e+00, 8.57942283e+00, 7.79418262e+00, 7.06103782e+00,
            6.46613664e+00, 5.85610944e+00, 5.30366351e+00, 4.74076635e+00,
            4.21611510e+00, 3.66232718e+00, 3.10619495e+00, 2.53497122e+00,
            1.98027816e+00, 1.38543959e+00, 8.18703781e-01, 2.49900259e-01,
            -2.76135665e-01, -7.58744341e-01, -1.16041714e+00, -1.40698611e+00,
            -1.54860906e+00, -1.50330449e+00, -1.31265337e+00, -9.75833813e-01,
            -5.23414842e-01, 6.43666620e-03, 5.50886150e-01, 1.16029829e+00,
            1.73313607e+00, 2.33306103e+00, 2.87948578e+00, 3.42592455e+00,
            3.93953357e+00, 4.41939616e+00, 4.87874672e+00, 5.32239162e+00,
            5.70678798e+00, 6.09397684e+00, 6.43869764e+00, 6.77035391e+00,
            7.08163966e+00, 7.34420969e+00, 7.61606210e+00, 7.84589533e+00,
            8.07298677e+00, 8.27414041e+00, 8.45476601e+00, 8.62785532e+00
        ]),
        atol=1)


def test_fmcw_phase_noise_py():
    tx_channel = dict(
        location=(0, 0, 0)
    )

    pn_f = np.array([1000, 10000, 100000, 1000000])
    pn_power = np.array([-44, -60, -56, -69])

    tx = Transmitter(f=[24.125e9-50e6, 24.125e9+50e6],
                     t=80e-6,
                     tx_power=20,
                     prp=100e-6,
                     pulses=1,
                     pn_f=pn_f,
                     pn_power=pn_power,
                     channels=[tx_channel])

    rx_channel = dict(
        location=(0, 0, 0)
    )

    rx = Receiver(fs=2e6,
                  noise_figure=12,
                  rf_gain=20,
                  load_resistor=500,
                  baseband_gain=30,
                  channels=[rx_channel])

    radar = Radar(transmitter=tx, receiver=rx, seed=12345, validation=True)

    target_1 = dict(location=(150, 0, 0), speed=(0, 0, 0), rcs=100, phase=0)
    target_2 = dict(location=(80, 0, 0), speed=(0, 0, 0), rcs=40, phase=0)

    targets = [target_1, target_2]

    data = simpy(radar, targets, noise=False)
    data_matrix = data['baseband']

    range_window = signal.windows.chebwin(radar.samples_per_pulse, at=60)
    range_profile = proc.range_fft(data_matrix, range_window)

    range_profile = 20 * \
        np.log10(np.abs(range_profile[0, 0, :]))

    npt.assert_almost_equal(
        range_profile,
        np.array([
            -8.43630867e+00, -8.30097621e+00, -8.17382738e+00, -8.06482062e+00,
            -7.98373469e+00, -7.94024100e+00, -7.94414553e+00, -8.00584348e+00,
            -8.13694662e+00, -8.35120140e+00, -8.66584730e+00, -9.10378229e+00,
            -9.69872801e+00, -1.04694738e+01, -1.15337325e+01, -1.30321718e+01,
            -1.52505875e+01, -1.88208993e+01, -2.42003567e+01, -2.31844085e+01,
            2.73748547e+00, -1.28996664e+01, -1.70845998e+01, -1.46821473e+01,
            -1.29571463e+01, -1.17512448e+01, -1.08919279e+01, -1.02764840e+01,
            -9.84139368e+00, -9.60047338e+00, -9.47070070e+00, -9.43646916e+00,
            -9.48143233e+00, -9.59154356e+00, -9.75360344e+00, -9.95409635e+00,
            -1.01782924e+01, -1.04096733e+01, -1.06299136e+01, -1.08195095e+01,
            -1.09593674e+01, -1.10332135e+01, -1.10302697e+01, -1.09472861e+01,
            -1.07889966e+01, -1.05677416e+01, -1.02953451e+01, -9.99516692e+00,
            -9.67903610e+00, -9.36054589e+00, -9.04861624e+00, -8.81250440e+00,
            -4.89061556e+00, -1.49615600e+00, 4.70509884e-01, -9.16015921e+00,
            -7.96860686e+00, -7.89543798e+00, -7.88108485e+00, -7.91900311e+00,
            -8.00654352e+00, -8.13934045e+00, -8.33480562e+00, -8.56826823e+00,
            -8.85083202e+00, -9.17713433e+00, -9.54084759e+00, -9.93127399e+00,
            -1.03314196e+01, -1.07159633e+01, -1.10501347e+01, -1.12913182e+01,
            -1.13955601e+01, -1.13290470e+01, -1.10800053e+01, -1.06633830e+01,
            -1.01147943e+01, -9.47822799e+00, -8.79508156e+00, -8.09839268e+00,
            -7.41171869e+00, -6.75045080e+00, -6.12381505e+00, -5.53668213e+00,
            -4.99085139e+00, -4.48680329e+00, -4.02146396e+00, -3.59129779e+00,
            -3.19093049e+00, -2.81257678e+00, -2.44430272e+00, -2.02948402e+00,
            -2.21551967e+00, -5.69525195e-01, 4.14610226e-03, 9.19276028e-01,
            2.04209289e+00, 2.46022701e+00, 1.70460331e+01, 4.28687414e+01,
            4.94608629e+01, 4.45268061e+01, 2.32806391e+01, -1.99447486e+00,
            -3.01387148e-01, -1.17278631e+00, -2.08912791e+00, -2.94943131e+00,
            -1.29670717e+00, -4.35336243e+00, -4.82410802e+00, -5.56778831e+00,
            -6.33010266e+00, -7.12356274e+00, -7.96409423e+00, -8.86693130e+00,
            -9.84660744e+00, -1.09118080e+01, -1.20747624e+01, -1.33349307e+01,
            -1.46680762e+01, -1.59960174e+01, -1.71425100e+01, -1.78292228e+01,
            -1.78304593e+01, -1.71968237e+01, -1.62039570e+01, -1.51048801e+01,
            -1.40395532e+01, -1.30682853e+01, -1.22100315e+01, -1.14480803e+01,
            -1.17896574e+01, -8.97426498e+00, -8.17824089e+00, -9.70008446e+00,
            -8.89131152e+00, -8.60708347e+00, -8.38579719e+00, -8.21829887e+00,
            -8.09905911e+00, -8.02452311e+00, -7.98985336e+00, -7.99103612e+00,
            -8.02517096e+00, -8.08771751e+00, -8.17379187e+00, -8.27783009e+00,
            -8.39350977e+00, -8.51375362e+00, -8.63086056e+00, -8.73680193e+00,
            -8.82370729e+00, -8.88451922e+00, -8.91373725e+00, -8.90812054e+00,
            -8.86718234e+00, -8.79335573e+00, -8.69178596e+00, -8.56981502e+00]),
        decimal=2)
