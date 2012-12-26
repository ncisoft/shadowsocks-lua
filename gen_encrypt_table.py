#!/usr/bin/env python

import string
import hashlib
import struct
import sys
import getopt

def get_table(key):
	m = hashlib.md5()
	m.update(key)
	s = m.digest()
	(a, b) = struct.unpack('<QQ', s)
	table = [c for c in string.maketrans('', '')]
	for i in xrange(1, 1024):
		table.sort(lambda x, y: int(a % (ord(x) + i) - a % (ord(y) + i)))
	return table

if __name__ == '__main__':
	KEY = None
	optlist, args = getopt.getopt(sys.argv[1:], 'k:')
	for key, value in optlist:
		if key == '-k':
			KEY = value
	if KEY is None or len(KEY) == 0:
		print 'Usage: gen_encrypt_table.py -k "you-key-here"'
		sys.exit(0)

	KEY = "Santen!vpn!"
	encrypt_table = ''.join(get_table(KEY))
	decrypt_table = string.maketrans(encrypt_table, string.maketrans('', ''))
	out = '-- KEY = "' + KEY + '"\n\n'
	out = out + "local encrypt_table = {"
	for i in range(len(encrypt_table)):
		if i % 16 ==0:
			out = out + "\n    "
		if i == 255:
			out = out + str(ord(encrypt_table[i]))
		else:
			out = out + str(ord(encrypt_table[i])) + ", "
	out = out + "\n}" + "\n\n"
	out = out + "local decrypt_table = {"
	for i in range(len(decrypt_table)):
		if i % 16 ==0:
			out = out + "\n    "
		if i == 255:
			out = out + str(ord(decrypt_table[i]))
		else:
			out = out + str(ord(decrypt_table[i])) + ", "
	out = out + "\n}" + "\n\n"
	out = out + "return {\n"
	out = out + "    " + "local_outgoing = encrypt_table, local_incoming = decrypt_table, \n"
	out = out + "    " + "remote_outgoing = decrypt_table, remote_incoming = encrypt_table \n"
	out = out + "}\n"
	print out

