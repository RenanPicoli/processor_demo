# -*- coding: utf-8 -*-
"""
Created on Thu Dec  7 16:39:45 2023

@author: EVHC
"""
'''
Text Editor
-------------------------------------------------------------
'''

'''import string as s'''
import tkinter as tk
from tkinter import ttk, simpledialog
from tkinter.filedialog import askopenfilename, asksaveasfilename

import serial

def shell():
   def open_file():
       filepath = askopenfilename(
           filetypes=[('Text Files', '*.txt'), ('All Files', '*.*')]
       )

       if not filepath:
           return

       txt_edit.delete(1.0, tk.END)
       with open(filepath, 'r') as input_file:
           text = input_file.read()
           txt_edit.insert(tk.END, text)
           txt_edit.tag_add("start","1.0","1.5")
           txt_edit.tag_config("start", background= "blue", foreground= "white")
           label = ttk.Label(txt_edit,text="arte",background='blue',foreground='white')
       window.title(f'TextEditor - {filepath}')

   def save_file():
       filepath = asksaveasfilename(
           defaultextension='txt',
           filetypes=[('Text Files', '*.txt'), ('All Files', '*.*')],
       )

       if not filepath:
           return

       with open(filepath, 'w') as output_file:
           text = txt_edit.get(1.0, tk.END)
           output_file.write(text)
       window.title(f'Text Editor - {filepath}')
       
   def continue_fn():
       b=0x80.to_bytes(1,'big')
       enter="\r\n".encode('utf-8')
       binary = b#+enter
       barr = bytearray(binary)
       ser.write(barr)
       
       text = txt_edit.get(1.0, tk.END)+"> continue\n"+\
                       ' '.join(list(map(hex,binary)))+'\n'
       txt_edit.delete(1.0, tk.END)
       txt_edit.insert(1.0, text)
       return
   
   def breakpoint_fn():
       b=0x40.to_bytes(1,'big')
       enter="\r\n".encode('utf-8')
       binary = b#+enter
       barr = bytearray(binary)
       ser.write(barr)
       
       text = txt_edit.get(1.0, tk.END)+"> breakpoint\n"+\
                   ' '.join(list(map(hex,binary)))+'\n'
       txt_edit.delete(1.0, tk.END)
       txt_edit.insert(1.0, text)
       return
       
   def next_fn():
       b=0x20.to_bytes(1,'big')
       enter="\r\n".encode('utf-8')
       binary = b#+enter
       barr = bytearray(binary)
       ser.write(barr)
       
       text = txt_edit.get(1.0, tk.END)+"> next\n"+\
           ' '.join(list(map(hex,binary)))+'\n'
       txt_edit.delete(1.0, tk.END)
       txt_edit.insert(1.0, text)
       return
       
   def inject_fn():
       b=0x10.to_bytes(1,'big')
       enter="\r\n".encode('utf-8')
       instruction_value=get_32bit_hex()
       binary = b+instruction_value.to_bytes(4, 'big')#+enter
       barr = bytearray(binary)
       ser.write(barr)
       
       text = txt_edit.get(1.0, tk.END)+"> inject "+\
               hex(instruction_value)+"\n"+\
               ' '.join(list(map(hex,binary)))+'\n'
       txt_edit.delete(1.0, tk.END)
       txt_edit.insert(1.0, text)
       return
       
   def set_reg_fn():
       b=0x08.to_bytes(1,'big')
       enter="\r\n".encode('utf-8')
       reg=get_8bit_int()
       value=get_32bit_hex()
       binary = b+reg.to_bytes(1, 'big')+value.to_bytes(4, 'big')#+enter
       barr = bytearray(binary)
       ser.write(barr)
       
       text = txt_edit.get(1.0, tk.END)+"> set_reg "+\
               str(reg)+" "+hex(value)+"\n"+\
               ' '.join(list(map(hex,binary)))+'\n'
       txt_edit.delete(1.0, tk.END)
       txt_edit.insert(1.0, text)
       return
       
   def get_reg_fn():
       b=0x04.to_bytes(1,'big')
       enter="\r\n".encode('utf-8')
       reg=get_8bit_int()
       binary = b+reg.to_bytes(1, 'big')#+enter
       barr = bytearray(binary)
       ser.write(barr)
	   
       response_bytearray = ser.read(4) # reads 4 bytes
       
       text = txt_edit.get(1.0, tk.END)+"> get_reg "+\
               str(reg)+"\n"+\
               ' '.join(list(map(hex,binary)))+'\n'
       # reverses the byte array (LSB is received first) then prints in hex
       text =  text+'0x'+response_bytearray[::-1].hex()+'\n'
	   
       txt_edit.delete(1.0, tk.END)
       txt_edit.insert(1.0, text)
       return
       
   def set_mem_fn():
       b=0x02.to_bytes(1,'big')
       enter="\r\n".encode('utf-8')
       memory_address=get_32bit_hex()
       value=get_32bit_hex()
       binary = b+memory_address.to_bytes(4, 'big')+\
                       value.to_bytes(4, 'big')#+enter
       barr = bytearray(binary)
       ser.write(barr)
       
       text = txt_edit.get(1.0, tk.END)+"> set_mem "+\
               hex(memory_address)+" "+hex(value)+"\n"+\
               ' '.join(list(map(hex,binary)))+'\n'
	   
       txt_edit.delete(1.0, tk.END)
       txt_edit.insert(1.0, text)
       return
       
   def get_mem_fn():
       b=0x01.to_bytes(1,'big')
       enter="\r\n".encode('utf-8')
       memory_address=get_32bit_hex()
       binary = b+memory_address.to_bytes(4, 'big')#+enter
       barr = bytearray(binary)
       ser.write(barr)
	   
       response_bytearray = ser.read(4) # reads 4 bytes
       
       text = txt_edit.get(1.0, tk.END)+"> get_mem "+\
               hex(memory_address)+"\n"+\
               ' '.join(list(map(hex,binary)))+'\n'
       # reverses the byte array (LSB is received first) then prints in hex
       text =  text+'0x'+response_bytearray[::-1].hex()+'\n'
	   
       txt_edit.delete(1.0, tk.END)
       txt_edit.insert(1.0, text)
       return
       
   def set_brk_fn():
       b=0x03.to_bytes(1,'big')
       enter="\r\n".encode('utf-8')
       instruction_value=get_32bit_hex()
       binary = b+instruction_value.to_bytes(4, 'big')#+enter
       barr = bytearray(binary)
       ser.write(barr)
       
       text = txt_edit.get(1.0, tk.END)+"> set_brk "+\
               hex(instruction_value)+"\n"+\
               ' '.join(list(map(hex,binary)))+'\n'
       txt_edit.delete(1.0, tk.END)
       txt_edit.insert(1.0, text)
       return
       
   def clr_brk_fn():
       b=0x05.to_bytes(1,'big')
       enter="\r\n".encode('utf-8')
       brk=get_8bit_int_brk()
       binary = b+brk.to_bytes(1, 'big')#+enter
       barr = bytearray(binary)
       ser.write(barr)
	          
       text = txt_edit.get(1.0, tk.END)+"> clr_brk "+\
               str(brk)+"\n"+\
               ' '.join(list(map(hex,binary)))+'\n'
	   
       txt_edit.delete(1.0, tk.END)
       txt_edit.insert(1.0, text)
       return
       
   def clr_all_brk_fn():
       b=0x06.to_bytes(1,'big')
       enter="\r\n".encode('utf-8')
       binary = b#+enter
       barr = bytearray(binary)
       ser.write(barr)
       
       text = txt_edit.get(1.0, tk.END)+"> clr_all_brk\n"+\
           ' '.join(list(map(hex,binary)))+'\n'
       txt_edit.delete(1.0, tk.END)
       txt_edit.insert(1.0, text)
       return
   
   # returns a int
   def get_32bit_hex():
       # window = tk.Tk()
       # window.title('Select bytes')
       # window.rowconfigure(0, minsize=800, weight=1)
       # window.columnconfigure(16, minsize=800, weight=1)
       # fr_buttons = tk.Frame(window, relief=tk.RAISED, bd=2)
       # btns=[]
       # global value
       # value = tk.IntVar()
       # for i in range(7):
       #     btns.append(tk.Button(fr_buttons, text=str(i), command=button_cmd(i)))
       #     btns[i].grid(row=i, column=0)
       # #window.wait_variable(value)
       # return value.get().to_bytes(1,'big')        label_status = ttk.Label(selection_window,text="Selecione o status:").pack()
       
       # combo_byte = ttk.Combobox(window, values=[hex(i) for i in range(256)])
       # combo_byte.pack()        
       # def set_byte(event):
       #     selected_option = combo_byte.get()
       #     print("You selected:", selected_option)
       #     value=selected_option        
       # combo_byte.bind("<<ComboboxSelected>>", set_byte)
       
       string = simpledialog.askstring("string", "Digite hexadecimal\n(8 dígitos)")
       def ishex(c):
           if c in "abcdefABCDEF0123456789":
               return True
           else:
               return False
       def is_not_hex(c):
           return not ishex(c)
       
       while(len(string) != 8 or any(map(is_not_hex,string))):
           string = simpledialog.askstring("string", "Digite hexadecimal\n(8 dígitos)")
       value = int(string,16)
       return value   

   # returns a int
   def get_8bit_int_brk():
       
       value = simpledialog.askinteger("Breakpoint", "Digite índice do breakpoint\n(0 a 7)")
       
       while(value < 0 or value > 7):
           value = simpledialog.askinteger("Breakpoint", "Digite índice do breakpoint\n(0 a 7)")
       return value   

   # returns a int
   def get_8bit_int():
       
       value = simpledialog.askinteger("registrador", "Digite número do registrador\n(0 a 31)")
       
       while(value < 0 or value > 31):
           value = simpledialog.askinteger("registrador", "Digite número do registrador\n(0 a 31)")
       return value

   global ser
   
   try:
       ser = serial.Serial("COM7",2400,timeout=1)
   except:
       ser = serial.Serial("/dev/pts/4",9600)
   
   window = tk.Tk()
   window.title('Debugger Shell')
   window.rowconfigure(0, minsize=300, weight=1)
   window.columnconfigure(1, minsize=300, weight=1)

   txt_edit = tk.Text(window)
   fr_buttons = tk.Frame(window, relief=tk.RAISED, bd=2)
   btn_open = tk.Button(fr_buttons, text='Open', command=open_file)
   btn_save = tk.Button(fr_buttons, text='Save As...', command=save_file)
   btn_continue = tk.Button(fr_buttons, text='continue', command=continue_fn)
   btn_breakpoint = tk.Button(fr_buttons, text='breakpoint', command=breakpoint_fn)
   btn_next = tk.Button(fr_buttons, text="next",command=next_fn)
   btn_inject = tk.Button(fr_buttons, text="inject",command=inject_fn)
   btn_set_reg = tk.Button(fr_buttons, text="set register",command=set_reg_fn)
   btn_get_reg = tk.Button(fr_buttons, text="get register",command=get_reg_fn)
   btn_set_mem = tk.Button(fr_buttons, text="set memory",command=set_mem_fn)
   btn_get_mem = tk.Button(fr_buttons, text="get memory",command=get_mem_fn)
   btn_set_brk = tk.Button(fr_buttons, text="set breakpoint",command=set_brk_fn)
   btn_clr_brk = tk.Button(fr_buttons, text="clear breakpoint",command=clr_brk_fn)
   btn_clr_all_brk = tk.Button(fr_buttons, text="clear all bkpt",command=clr_all_brk_fn)

   btn_open.grid(row=0, column=0, sticky='ew', padx=5, pady=5)
   btn_save.grid(row=1, column=0, sticky='ew', padx=5)
   btn_continue.grid(row=2, column=0, sticky='ew', padx=5)
   btn_breakpoint.grid(row=3, column=0, sticky='ew', padx=5)
   btn_next.grid(row=4, column=0, sticky='ew', padx=5)
   btn_inject.grid(row=5, column=0, sticky='ew', padx=5)
   btn_set_reg.grid(row=6, column=0, sticky='ew', padx=5)
   btn_get_reg.grid(row=7, column=0, sticky='ew', padx=5)
   btn_set_mem.grid(row=8, column=0, sticky='ew', padx=5)
   btn_get_mem.grid(row=9, column=0, sticky='ew', padx=5)
   btn_set_brk.grid(row=10, column=0, sticky='ew', padx=5)
   btn_clr_brk.grid(row=11, column=0, sticky='ew', padx=5)
   btn_clr_all_brk.grid(row=12, column=0, sticky='ew', padx=5)

   fr_buttons.grid(row=0, column=0, sticky='ns')
   txt_edit.grid(row=0, column=1, sticky='nsew')

   window.mainloop()


if __name__ == '__main__':
  shell()
