from PIL import Image
import struct

def image_to_binary(input_image_path, output_bin_path):
    # Abre a imagem
    img = Image.open(input_image_path).convert("RGB")

    # Redimensiona para 640x480
    img = img.resize((640, 480), Image.LANCZOS)

    width, height = img.size  # agora sempre 640x480

    with open(output_bin_path, "wb") as f:
        for y in range(height):
            for x in range(width):
                r, g, b = img.getpixel((x, y))

                # Monta a palavra de 32 bits: 0x00RRGGBB
                word = (0 << 24) | (r << 16) | (g << 8) | b

                # Escreve em formato binário (unsigned int, 4 bytes, little-endian)
                f.write(struct.pack("<I", word))

# Exemplo de uso:
image_to_binary("EX1A9227.jpg", "img_raster.bin")