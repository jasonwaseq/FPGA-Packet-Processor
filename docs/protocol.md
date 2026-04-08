# Protocol Reference

## Transport Frame

Byte order on the wire:

```text
0x7E | ver | msg_type | flags | seq | len_hi | len_lo | payload[0:N-1] | crc_hi | crc_lo | 0x7E
```

- `ver`: currently `0x01`
- `msg_type`: transport payload type
- `flags`: reserved in v1
- `seq`: host-selected sequence number echoed in responses
- `len`: payload length in bytes, big-endian
- `crc`: CRC16-CCITT over `ver..payload`

Escaping:

- `0x7E` is replaced with `0x7D 0x5E`
- `0x7D` is replaced with `0x7D 0x5D`

Transport message types:

- `0x01`: `CMD_REQ`
- `0x02`: `CMD_RESP`
- `0x10`: `DATA_PACKET`
- `0x11`: `PKT_RESULT`
- `0x12`: `PKT_FORWARD`
- `0x13`: reserved for future event/log frames

## Packet Format

The internal packet format is a fixed 20-byte header plus payload.

```text
0  : version/hdr_len
1  : protocol
2  : flags
3  : ttl
4-5: total_length
6-7: payload_length
8-9: src_addr
10-11: dst_addr
12-13: src_port
14-15: dst_port
16-17: packet_id
18-19: hdr_checksum
20.. : payload
```

Validation rules:

- `version == 1`
- `hdr_len == 5`
- `total_length == received_packet_bytes`
- `payload_length == total_length - 20`
- `ttl != 0`
- one’s-complement header checksum is valid

## Rule Image

Each rule is a 24-byte image written atomically through `WRITE_RULE`.

```text
0  : valid
1  : match_en
2  : action
3  : rewrite_en
4-5: src_addr_value
6-7: src_addr_mask
8-9: dst_addr_value
10-11: dst_addr_mask
12-13: src_port_value
14-15: dst_port_value
16 : protocol_value
17 : rewrite_flags_value
18-19: rewrite_dst_addr
20-21: rewrite_dst_port
22-23: reserved
```

`match_en` bits:

- bit `0`: source address match enabled
- bit `1`: destination address match enabled
- bit `2`: source port match enabled
- bit `3`: destination port match enabled
- bit `4`: protocol match enabled

`rewrite_en` bits:

- bit `0`: decrement TTL
- bit `1`: overwrite flags
- bit `2`: overwrite destination port
- bit `3`: overwrite destination address

Action codes:

- `0`: drop
- `1`: accept
- `2`: count only
- `3`: rewrite

Rule priority is strict first-match, lowest index wins.

## Commands

`CMD_REQ` payload is `[opcode][args...]`.

`CMD_RESP` payload is `[opcode][status][data...]`.

Supported opcodes:

- `0x00`: `PING`
- `0x01`: `GET_INFO`
- `0x02`: `SOFT_RESET`
- `0x03`: `CLEAR_COUNTERS`
- `0x04`: `SET_MODE`
- `0x05`: `GET_MODE`
- `0x10`: `WRITE_RULE`
- `0x11`: `CLEAR_RULE`
- `0x12`: `CLEAR_ALL_RULES`
- `0x13`: `READ_RULE`
- `0x14`: `SET_DEFAULT_ACTION`
- `0x15`: `SET_VERBOSE`
- `0x20`: `READ_COUNTERS`
- `0x21`: `READ_LAST_RESULT`
- `0x22`: `READ_STATUS`

Status codes:

- `0`: OK
- `1`: bad opcode
- `2`: bad length
- `3`: bad parameter
- `4`: busy
- `5`: bad rule index
- `6`: bad mode
- `7`: internal error

## Results

`PKT_RESULT` payload:

```text
0  : result_flags
1  : mode
2  : rule_id
3  : action
4  : error_code
5  : protocol
6-7: packet_id
8-9: src_addr
10-11: dst_addr_final
12-13: src_port
14-15: dst_port_final
16-17: total_length_final
18-19: payload_length_final
```

`PKT_FORWARD` payload:

```text
0  : result_flags
1  : rule_id
2  : action
3  : error_code
4..: final packet bytes
```

## Modes

- `0`: `INSPECT`
  - emit `PKT_RESULT` for every packet
- `1`: `INLINE`
  - emit `PKT_FORWARD` for accepted/rewritten packets
  - emit `PKT_RESULT` for dropped/count-only/error cases
- `2`: `BENCHMARK`
  - suppress unsolicited packet responses
  - rely on counters and latency registers
