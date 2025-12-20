
import struct

def expand(input_file,output_file):
    # a trick to overcome a problem with SDRAM reading:
    # odd-numbered rows are skipped (WHY??), so I fill them with zeros
    # this is specific to a sdram chip with row containing 1024 columns

    # reads input file
    inp = open(input_file,'rb')

    #creates output file
    f = open(output_file,'wb')

    i = 0
    while True:
        # reads 4 bytes (1 word)
        word = inp.read(4)
        if not word:
            break # nothing was read, nothing to do
        else:
            f.write(struct.pack("<I",int.from_bytes(word,byteorder='little'))) # word is of type bytes, convert it to int with little endian order
            if i % 1024 == 1023:
                # insert a zeroed row
                for i in range(1024):
                    f.write(struct.pack("<I", 0))
            i = i+1

    inp.close()
    f.close()

# exemplo de uso
expand("img_raster.bin","img_expanded.bin")