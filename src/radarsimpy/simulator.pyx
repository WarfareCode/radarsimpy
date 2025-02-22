# distutils: language = c++
"""
A Python module for radar simulation

---

- Copyright (C) 2018 - PRESENT  radarsimx.com
- E-mail: info@radarsimx.com
- Website: https://radarsimx.com

::

    ██████╗  █████╗ ██████╗  █████╗ ██████╗ ███████╗██╗███╗   ███╗██╗  ██╗
    ██╔══██╗██╔══██╗██╔══██╗██╔══██╗██╔══██╗██╔════╝██║████╗ ████║╚██╗██╔╝
    ██████╔╝███████║██║  ██║███████║██████╔╝███████╗██║██╔████╔██║ ╚███╔╝ 
    ██╔══██╗██╔══██║██║  ██║██╔══██║██╔══██╗╚════██║██║██║╚██╔╝██║ ██╔██╗ 
    ██║  ██║██║  ██║██████╔╝██║  ██║██║  ██║███████║██║██║ ╚═╝ ██║██╔╝ ██╗
    ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝╚═╝     ╚═╝╚═╝  ╚═╝

"""


import numpy as np

from radarsimpy.includes.zpvector cimport Vec3
from radarsimpy.includes.type_def cimport vector
from radarsimpy.includes.type_def cimport float_t, int_t
from radarsimpy.includes.radarsimc cimport Simulator
from radarsimpy.lib.cp_radarsimc cimport cp_RxChannel
from radarsimpy.includes.radarsimc cimport Receiver
from radarsimpy.includes.radarsimc cimport Radar
from radarsimpy.lib.cp_radarsimc cimport cp_TxChannel, cp_Transmitter
from radarsimpy.includes.radarsimc cimport Transmitter
from radarsimpy.includes.radarsimc cimport Mem_Copy_Vec3
from radarsimpy.includes.radarsimc cimport IsFreeTier
from radarsimpy.lib.cp_radarsimc cimport cp_Point
from radarsimpy.includes.radarsimc cimport Point

from libc.stdlib cimport malloc, free

cimport cython
cimport numpy as np

np_float = np.float32


@cython.cdivision(True)
@cython.boundscheck(False)
@cython.wraparound(False)
cpdef simc(radar, targets, noise=True):
    """
    simc(radar, targets, noise=True)

    Radar simulator with C++ engine

    :param Radar radar:
        Radar model
    :param list[dict] targets:
        Ideal point target list

        [{

        - **location** (*numpy.1darray*) --
            Location of the target (m), [x, y, z]
        - **rcs** (*float*) --
            Target RCS (dBsm)
        - **speed** (*numpy.1darray*) --
            Speed of the target (m/s), [vx, vy, vz]. ``default
            [0, 0, 0]``
        - **phase** (*float*) --
            Target phase (deg). ``default 0``

        }]

        *Note*: Target's parameters can be specified with
        ``Radar.timestamp`` to customize the time varying property.
        Example: ``location=(1e-3*np.sin(2*np.pi*1*radar.timestamp), 0, 0)``
    :param bool noise:
        Flag to enable noise calculation. ``default True``

    :return:
        {

        - **baseband** (*numpy.3darray*) --
            Time domain complex (I/Q) baseband data.
            ``[channes/frames, pulses, samples]``

            *Channel/frame order in baseband*

            *[0]* ``Frame[0] -- Tx[0] -- Rx[0]``

            *[1]* ``Frame[0] -- Tx[0] -- Rx[1]``

            ...

            *[N]* ``Frame[0] -- Tx[1] -- Rx[0]``

            *[N+1]* ``Frame[0] -- Tx[1] -- Rx[1]``

            ...

            *[M]* ``Frame[1] -- Tx[0] -- Rx[0]``

            *[M+1]* ``Frame[1] -- Tx[0] -- Rx[1]``

        - **timestamp** (*numpy.3darray*) --
            Refer to Radar.timestamp

        }
    :rtype: dict
    """
    cdef Simulator[float_t] sim_c

    cdef vector[Point[float_t]] point_vt
    cdef Transmitter[float_t] tx_c
    cdef Receiver[float_t] rx_c
    cdef Radar[float_t] radar_c

    cdef Transmitter[float_t] interf_tx_c
    cdef Receiver[float_t] interf_rx_c
    cdef Radar[float_t] interf_radar_c

    cdef int_t frames_c = radar.time_prop["frame_size"]
    cdef int_t channles_c = radar.array_prop["size"]
    cdef int_t pulses_c = radar.radar_prop["transmitter"].waveform_prop["pulses"]
    cdef int_t samples_c = radar.sample_prop["samples_per_pulse"]

    cdef int_t bbsize_c = channles_c*frames_c*pulses_c*samples_c

    cdef int_t chstride_c = pulses_c * samples_c
    cdef int_t psstride_c = samples_c
    
    cdef float_t[:, :, :] locx_mv, locy_mv, locz_mv
    cdef float_t[:, :, :] spdx_mv, spdy_mv, spdz_mv
    cdef float_t[:, :, :] rotx_mv, roty_mv, rotz_mv
    cdef float_t[:, :, :] rrtx_mv, rrty_mv, rrtz_mv

    cdef vector[Vec3[float_t]] loc_vt
    cdef vector[Vec3[float_t]] spd_vt
    cdef vector[Vec3[float_t]] rot_vt
    cdef vector[Vec3[float_t]] rrt_vt

    cdef vector[Vec3[float_t]] interf_loc_vt
    cdef vector[Vec3[float_t]] interf_spd_vt
    cdef vector[Vec3[float_t]] interf_rot_vt
    cdef vector[Vec3[float_t]] interf_rrt_vt

    cdef int_t idx_c

    if IsFreeTier():
        if len(targets) > 3:
            raise Exception("You're currently using RadarSimPy's FreeTier, which limits RCS simulation to 3 maximum targets. Please consider supporting my work by upgrading to the standard version. Just choose any amount greater than zero on https://radarsimx.com/product/radarsimpy/ to access the standard version download links. Your support will help improve the software. Thank you for considering it.")

        if radar.radar_prop["transmitter"].txchannel_prop["size"] > 2:
            raise Exception("You're currently using RadarSimPy's FreeTier, which imposes a restriction on the maximum number of transmitter channels to 2. Please consider supporting my work by upgrading to the standard version. Just choose any amount greater than zero on https://radarsimx.com/product/radarsimpy/ to access the standard version download links. Your support will help improve the software. Thank you for considering it.")
        
        if radar.radar_prop["receiver"].rxchannel_prop["size"] > 2:
            raise Exception("You're currently using RadarSimPy's FreeTier, which imposes a restriction on the maximum number of receiver channels to 2. Please consider supporting my work by upgrading to the standard version. Just choose any amount greater than zero on https://radarsimx.com/product/radarsimpy/ to access the standard version download links. Your support will help improve the software. Thank you for considering it.")

    ts_shape = np.shape(radar.time_prop["timestamp"])

    # Point Targets
    for _, tgt in enumerate(targets):
        loc = tgt["location"]
        spd = tgt.get("speed", (0, 0, 0))
        rcs = tgt["rcs"]
        phs = tgt.get("phase", 0)

        point_vt.push_back(
            cp_Point(loc, spd, rcs, phs, ts_shape)
        )

    # Transmitter
    tx_c = cp_Transmitter(radar)

    # Transmitter Channels
    for idx_c in range(0, radar.radar_prop["transmitter"].txchannel_prop["size"]):
        tx_c.AddChannel(cp_TxChannel(radar.radar_prop["transmitter"], idx_c))

    # Receiver
    rx_c = Receiver[float_t](
        <float_t> radar.radar_prop["receiver"].bb_prop["fs"],
        <float_t> radar.radar_prop["receiver"].rf_prop["rf_gain"],
        <float_t> radar.radar_prop["receiver"].bb_prop["load_resistor"],
        <float_t> radar.radar_prop["receiver"].bb_prop["baseband_gain"]
    )

    for idx_c in range(0, radar.radar_prop["receiver"].rxchannel_prop["size"]):
        rx_c.AddChannel(cp_RxChannel(radar.radar_prop["receiver"], idx_c))

    # Radar
    cdef float_t[:] loc_mv, spd_mv, rot_mv, rrt_mv
    radar_c = Radar[float_t](tx_c, rx_c)

    if len(np.shape(radar.radar_prop["location"])) == 4:
        locx_mv = radar.radar_prop["location"][:,:,:,0].astype(np_float)
        locy_mv = radar.radar_prop["location"][:,:,:,1].astype(np_float)
        locz_mv = radar.radar_prop["location"][:,:,:,2].astype(np_float)
        spdx_mv = radar.radar_prop["speed"][:,:,:,0].astype(np_float)
        spdy_mv = radar.radar_prop["speed"][:,:,:,1].astype(np_float)
        spdz_mv = radar.radar_prop["speed"][:,:,:,2].astype(np_float)
        rotx_mv = radar.radar_prop["rotation"][:,:,:,0].astype(np_float)
        roty_mv = radar.radar_prop["rotation"][:,:,:,1].astype(np_float)
        rotz_mv = radar.radar_prop["rotation"][:,:,:,2].astype(np_float)
        rrtx_mv = radar.radar_prop["rotation_rate"][:,:,:,0].astype(np_float)
        rrty_mv = radar.radar_prop["rotation_rate"][:,:,:,1].astype(np_float)
        rrtz_mv = radar.radar_prop["rotation_rate"][:,:,:,2].astype(np_float)

        Mem_Copy_Vec3(&locx_mv[0,0,0], &locy_mv[0,0,0], &locz_mv[0,0,0], bbsize_c, loc_vt)
        Mem_Copy_Vec3(&spdx_mv[0,0,0], &spdy_mv[0,0,0], &spdz_mv[0,0,0], bbsize_c, spd_vt)
        Mem_Copy_Vec3(&rotx_mv[0,0,0], &roty_mv[0,0,0], &rotz_mv[0,0,0], bbsize_c, rot_vt)
        Mem_Copy_Vec3(&rrtx_mv[0,0,0], &rrty_mv[0,0,0], &rrtz_mv[0,0,0], bbsize_c, rrt_vt)

    else:
        loc_mv = radar.radar_prop["location"].astype(np_float)
        loc_vt.push_back(Vec3[float_t](&loc_mv[0]))

        spd_mv = radar.radar_prop["speed"].astype(np_float)
        spd_vt.push_back(Vec3[float_t](&spd_mv[0]))

        rot_mv = radar.radar_prop["rotation"].astype(np_float)
        rot_vt.push_back(Vec3[float_t](&rot_mv[0]))

        rrt_mv = radar.radar_prop["rotation_rate"].astype(np_float)
        rrt_vt.push_back(Vec3[float_t](&rrt_mv[0]))

    radar_c.SetMotion(loc_vt,
                      spd_vt,
                      rot_vt,
                      rrt_vt)

    cdef double * bb_real = <double *> malloc(bbsize_c*sizeof(double))
    cdef double * bb_imag = <double *> malloc(bbsize_c*sizeof(double))

    sim_c.Run(radar_c, point_vt, bb_real, bb_imag)

    baseband = np.zeros((frames_c*channles_c, pulses_c, samples_c), dtype=complex)

    cdef int_t ch_idx, p_idx, s_idx
    cdef int_t bb_idx
    for ch_idx in range(0, frames_c*channles_c):
        for p_idx in range(0, pulses_c):
            for s_idx in range(0, samples_c):
                bb_idx = ch_idx * chstride_c + p_idx * psstride_c + s_idx
                baseband[ch_idx, p_idx, s_idx] = bb_real[bb_idx] +  1j*bb_imag[bb_idx]

    if noise:
        baseband = baseband +\
            radar.sample_prop["noise"]*(
                np.random.randn(
                    frames_c*channles_c,
                    pulses_c,
                    samples_c,
                ) + \
                1j * np.random.randn(
                    frames_c*channles_c,
                    pulses_c,
                    samples_c,
                )
            )
    
    if radar.radar_prop["interf"] is not None:
        interf_radar_prop = radar.radar_prop["interf"].radar_prop
        """
        Transmitter
        """
        interf_tx_c = cp_Transmitter(radar.radar_prop["interf"])

        """
        Transmitter Channels
        """
        for idx_c in range(0, interf_radar_prop["transmitter"].txchannel_prop["size"]):
            interf_tx_c.AddChannel(cp_TxChannel(interf_radar_prop["transmitter"], idx_c))

        """
        Receiver
        """
        interf_rx_c = Receiver[float_t](
            <float_t> interf_radar_prop["receiver"].bb_prop["fs"],
            <float_t> interf_radar_prop["receiver"].rf_prop["rf_gain"],
            <float_t> interf_radar_prop["receiver"].bb_prop["load_resistor"],
            <float_t> interf_radar_prop["receiver"].bb_prop["baseband_gain"]
        )

        for idx_c in range(0, interf_radar_prop["receiver"].rxchannel_prop["size"]):
            interf_rx_c.AddChannel(cp_RxChannel(interf_radar_prop["receiver"], idx_c))

        interf_radar_c = Radar[float_t](interf_tx_c, interf_rx_c)

        if len(np.shape(interf_radar_prop["location"])) == 4:
            locx_mv = interf_radar_prop["location"][:,:,:,0].astype(np_float)
            locy_mv = interf_radar_prop["location"][:,:,:,1].astype(np_float)
            locz_mv = interf_radar_prop["location"][:,:,:,2].astype(np_float)
            spdx_mv = interf_radar_prop["speed"][:,:,:,0].astype(np_float)
            spdy_mv = interf_radar_prop["speed"][:,:,:,1].astype(np_float)
            spdz_mv = interf_radar_prop["speed"][:,:,:,2].astype(np_float)
            rotx_mv = interf_radar_prop["rotation"][:,:,:,0].astype(np_float)
            roty_mv = interf_radar_prop["rotation"][:,:,:,1].astype(np_float)
            rotz_mv = interf_radar_prop["rotation"][:,:,:,2].astype(np_float)
            rrtx_mv = interf_radar_prop["rotation_rate"][:,:,:,0].astype(np_float)
            rrty_mv = interf_radar_prop["rotation_rate"][:,:,:,1].astype(np_float)
            rrtz_mv = interf_radar_prop["rotation_rate"][:,:,:,2].astype(np_float)

            Mem_Copy_Vec3(&locx_mv[0,0,0], &locy_mv[0,0,0], &locz_mv[0,0,0], bbsize_c, interf_loc_vt)
            Mem_Copy_Vec3(&spdx_mv[0,0,0], &spdy_mv[0,0,0], &spdz_mv[0,0,0], bbsize_c, interf_spd_vt)
            Mem_Copy_Vec3(&rotx_mv[0,0,0], &roty_mv[0,0,0], &rotz_mv[0,0,0], bbsize_c, interf_rot_vt)
            Mem_Copy_Vec3(&rrtx_mv[0,0,0], &rrty_mv[0,0,0], &rrtz_mv[0,0,0], bbsize_c, interf_rrt_vt)
                                                                           
        else:
            loc_mv = interf_radar_prop["location"].astype(np_float)
            interf_loc_vt.push_back(Vec3[float_t](&loc_mv[0]))

            spd_mv = interf_radar_prop["speed"].astype(np_float)
            interf_spd_vt.push_back(Vec3[float_t](&spd_mv[0]))

            rot_mv = interf_radar_prop["rotation"].astype(np_float)
            interf_rot_vt.push_back(Vec3[float_t](&rot_mv[0]))

            rrt_mv = interf_radar_prop["rotation_rate"].astype(np_float)
            interf_rrt_vt.push_back(Vec3[float_t](&rrt_mv[0]))

        interf_radar_c.SetMotion(interf_loc_vt,
                        interf_spd_vt,
                        interf_rot_vt,
                        interf_rrt_vt)

        sim_c.Interference(radar_c, interf_radar_c, bb_real, bb_imag)

        interference = np.zeros((frames_c*channles_c, pulses_c, samples_c), dtype=complex)

        for ch_idx in range(0, frames_c*channles_c):
            for p_idx in range(0, pulses_c):
                for s_idx in range(0, samples_c):
                    bb_idx = ch_idx * chstride_c + p_idx * psstride_c + s_idx
                    interference[ch_idx, p_idx, s_idx] = bb_real[bb_idx] +  1j*bb_imag[bb_idx]

    else:
        interference = None

    # free memory
    free(bb_real)
    free(bb_imag)

    return {"baseband": baseband,
            "timestamp": radar.time_prop["timestamp"],
            "interference": interference}
