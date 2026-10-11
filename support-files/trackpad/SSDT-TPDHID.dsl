/*
 * Intel ACPI Component Architecture
 * AML/ASL+ Disassembler version 20260408 (64-bit version)
 * Copyright (c) 2000 - 2026 Intel Corporation
 * 
 * Disassembling to symbolic ASL+ operators
 *
 * Disassembly of SSDT-TPDHID.aml
 *
 * Original Table Header:
 *     Signature        "SSDT"
 *     Length           0x0000011C (284)
 *     Revision         0x02
 *     Checksum         0x64
 *     OEM ID           "ZPSS"
 *     OEM Table ID     "TPDHID"
 *     OEM Revision     0x00000000 (0)
 *     Compiler ID      "INTL"
 *     Compiler Version 0x20260408 (539362312)
 */
DefinitionBlock ("", "SSDT", 2, "ZPSS", "TPDHID", 0x00000000)
{
    External (_SB_.PC00, DeviceObj)

    Scope (\_SB.PC00)
    {
        Device (ZTPD)
        {
            Name (_ADR, Zero)  // _ADR: Address
            Name (_HID, "ASUP1207")  // _HID: Hardware ID
            Name (_CID, EisaId ("PNP0C50") /* HID Protocol Device (I2C bus) */)  // _CID: Compatible ID
            Name (_UID, One)  // _UID: Unique ID
            Name (_S0W, 0x03)  // _S0W: S0 Device Wake State
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                Return (0x0F)
            }

            Method (_DSM, 4, Serialized)  // _DSM: Device-Specific Method
            {
                If ((Arg0 == 0x3CDFF6F7))
                {
                    If ((Arg2 == Zero))
                    {
                        If ((Arg1 == One))
                        {
                            Return (Buffer (One)
                            {
                                 0x03                                             // .
                            })
                        }
                    }

                    If ((Arg2 == One))
                    {
                        Return (One)
                    }
                }

                Return (Buffer (One)
                {
                     0x00                                             // .
                })
            }

            Method (XDSM, 4, Serialized)
            {
                If ((Arg2 == Zero))
                {
                    Return (Buffer (One)
                    {
                         0x03                                             // .
                    })
                }

                Return (One)
            }

            Method (_CRS, 0, NotSerialized)  // _CRS: Current Resource Settings
            {
                Name (BUF0, Buffer (0x48)
                {
                    /* 0000 */  0x8E, 0x1E, 0x00, 0x02, 0x00, 0x01, 0x02, 0x00,  // ........
                    /* 0008 */  0x00, 0x01, 0x06, 0x00, 0x80, 0x1A, 0x06, 0x00,  // ........
                    /* 0010 */  0x15, 0x00, 0x5C, 0x5F, 0x53, 0x42, 0x2E, 0x50,  // ..\_SB.P
                    /* 0018 */  0x43, 0x30, 0x30, 0x2E, 0x49, 0x32, 0x43, 0x33,  // C00.I2C3
                    /* 0020 */  0x00, 0x8C, 0x20, 0x00, 0x01, 0x00, 0x01, 0x00,  // .. .....
                    /* 0028 */  0x01, 0x00, 0x00, 0x01, 0x17, 0x00, 0x00, 0x19,  // ........
                    /* 0030 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                    /* 0038 */  0x00, 0x00, 0x17, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                    /* 0040 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x79, 0x00   // ......y.
                })
                Return (BUF0) /* \_SB_.PC00.ZTPD._CRS.BUF0 */
            }
        }
    }
}

