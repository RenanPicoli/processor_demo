/*
	Generates binary files from vhdl code of mini_rom.vhd for SRAM programming
	Generates a single file with 512Kx16bit data refering to data_in (input_vectors.txt) and 512Kx16 bit refering to desired values (desired_vectors.txt)
	Values are 32 bit wide, but LSB are stored in address 2n, and MSB are stored in addr 2n+1
	Example: data_in = 0x368F75BF
	addr[0]= 0x75BF
	addr[1]= 0x368F
	This file will fill completely DE2-115 SRAM as I move the assembly to that memory
	It will be downloaded using DE2 Control Panel
*/
//for printf, fopen, fgets, fwrite, etc.
#include <stdio.h>

//for malloc
#include <stdlib.h>

//for UINT_MAX
#include <limits.h>

//for strlen, strcpy, strncpy
#include <string.h>

//tolower, toupper
#include <ctype.h>

//number of instructions to store
//256 = 0x100
#define N_INSTR 256

//maximum length of line in text files
#define MAX_STR_LENGTH 200

//for the opcode dictionary
typedef struct
{
	char name[11];//up to 10 chars and one null byte
	char binary_string[7];//string containing up to 6 chars in {'0','1'} and one null byte
}node;

//function to convert hex strings to unsigned int
unsigned int hex2uint(char* str);

//function to convert hex strings to binary string
char* hex2bin(char* str);


//function to convert bin strings to unsigned int
unsigned int bin2uint(char* str);

//function to return index of  string in dictionary names, or -1 if fails
int find(node* dict, int dict_size, char* str);

int main(void){
	FILE *fp;//file pointer for read
	FILE *fp_types;//file pointer for read, contains the opcodes and codes for registers
	FILE *of;//file pointer for outputfile

	of=fopen("./sram_file_experimental.bin","wb");//NOTE THE 'b' in "wb" mode: opens a BINARY file for write, otherwise, will line ending chars
	if(of==NULL){
		printf("Erro ao criar o arquivo de saída!\n");
		return 1;
	}

	node* dictionary=NULL;
	char* tmp_str=calloc(MAX_STR_LENGTH,sizeof(char));//temporary string to store lines read from files
	char* instruction_str=calloc(MAX_STR_LENGTH,sizeof(char));//temporary string to store lines read from files
	char* comment_str=calloc(MAX_STR_LENGTH,sizeof(char));//temporary string to store single line comment read from files
	unsigned int *ptr=malloc(1*sizeof(unsigned int));//temporary pointer to store instruction generated from a single line of fp
	char **s=calloc(6,sizeof(char*));
	s[0]=calloc(MAX_STR_LENGTH,sizeof(char));//temporary string to store lines read from files
	s[1]=calloc(MAX_STR_LENGTH,sizeof(char));//temporary string to store lines read from files
	s[2]=calloc(MAX_STR_LENGTH,sizeof(char));//temporary string to store lines read from files
	s[3]=calloc(MAX_STR_LENGTH,sizeof(char));//temporary string to store lines read from files
	s[4]=calloc(MAX_STR_LENGTH,sizeof(char));//temporary string to store lines read from files
	s[5]=calloc(MAX_STR_LENGTH,sizeof(char));//temporary string to store lines read from files
	unsigned int instruction=0;//binary encoded
	if(ptr==NULL){
		printf("Erro ao alocar a memória para o ponteiro ptr\n");
		return 5;
	}
	if(tmp_str==NULL||instruction_str==NULL||comment_str==NULL){
		printf("Erro ao alocar a memória para o ponteiro tmp_str ou instruction_str ou comment_str\n");
		return 6;
	}
	fp=fopen("./microprocessor/mini_rom.vhd","r");//instructions will only be read
	fp_types=fopen("./microprocessor/my_types.vhd","r");//instructions will only be read
	if(fp==NULL){
		printf("Erro ao ler o arquivo mini_rom.vhd\n");
		return 2;
	}
	if(fp_types==NULL){
		printf("Erro ao ler o arquivo my_types.vhd\n");
		return 3;
	}
	int sscanf_retval=0;//to store sscanf return value to check if it was successful
	int fwrite_retval=0;//to store fwrite return value to check if it was successful
	int sscanf_retval_bin=0;
	int sscanf_retval_hex=0;

	printf("Parsing my_types.vhd\n");
	int j=0;
	while (!feof(fp_types)){
		fgets((char*)tmp_str,MAX_STR_LENGTH,fp_types);//reads a single line of fp_types, terminated with '\n', expects at most 199 chars
		sscanf_retval=sscanf(tmp_str,"constant %[a-zA-Z0-9&\"_ ] : %*[a-zA-Z0-9&\"_() ] := \"%[01]\" ;",s[0],s[1]);
		if(sscanf_retval>1){
			//printf("Opcode j=%d: %s := %s\n",j,s0,s1);
			dictionary = realloc(dictionary,(j+1)*sizeof(node));
			//TODO: convert s0, s1 to lower case
			strncpy(dictionary[j].name,s[0],11);
			strncpy(dictionary[j].binary_string,s[1],7);
			printf("Opcode j=%d: %s := %s\n",j,dictionary[j].name,dictionary[j].binary_string);
			j++;
		}
		fgetc(fp_types);//reads and discards the newline
	}
	printf("my_types.vhd parsed!\n");

	printf("Parsing mini_rom.vhd\n");
	int i=0;
	char binary_string[33];//string containing 32 chars in {'0','1'} and one null byte
	while (!feof(fp)){
		fgets((char*)tmp_str,MAX_STR_LENGTH,fp);//reads a single line of fp, terminated with '\n', expects at most 199 chars
		sscanf_retval=sscanf(tmp_str,"%d => %[a-zA-Z0-9&\"_ ],%*s",&i,instruction_str);//reads a single line of fp, with no spaces, terminated with '\n', expects 8 hexadecimal digits (32bit data)
		//TODO: convert instruction_str to lower case
		if(sscanf_retval>1){
			sscanf_retval=sscanf(instruction_str,"%s & %s & %s & %s & %s & %s",s[0],s[1],s[2],s[3],s[4],s[5]);//parses the instruction
			//printf("Instrução i=%d (%d): %s %s %s %s %s %s\n",i,sscanf_retval,s[0],s[1],s[2],s[3],s[4],s[5]);
			//printf("Instrução i=%d: %s\n",i,instruction_str);
			binary_string[0]='\0';
			printf("Instrução i=%d: ",i);
			for(int k=0;k<sscanf_retval;k++){
				printf("%s ",s[k]);
				int pos=find(dictionary,j,s[k]);
				if(pos!=-1){
					strcat(binary_string,dictionary[pos].binary_string);
				}else{
					//test for hex constant
					sscanf_retval_hex = sscanf(s[k],"x\"%[0-9a-fA-F]\"",s[k]);
					if(sscanf_retval_hex!=0){//is hex constant
						strcat(binary_string,hex2bin(s[k]));
					}else{
						sscanf_retval_bin = sscanf(s[k],"\"%[01]\"",s[k]);
						if(sscanf_retval_bin!=0){//is bin constant
							strcat(binary_string,s[k]);
						}else{
							printf("Constante inválida!\n");
							return -1;
						}
					}
				}
			}
			printf(" --> %s\n",binary_string);
			if(strlen(binary_string)!=32){
				printf("Erro de conversão, instrução não tem 32 bits!\n");
				return -2;
			}
			instruction = bin2uint(binary_string);
			fwrite_retval=fwrite(&instruction,sizeof(unsigned int),1,of);//writes the 32bit unsigned int
			if(fwrite_retval!=1){
				printf("Erro de fwrite!\ns");
				return 8;
			}
		}
		fgetc(fp);//reads and discards the newline
		//tmp_str[8]='\0';
		//printf("i:%d tmp_str:%s ",i,tmp_str);
		// *ptr=hex2uint(tmp_str);//stores in ptr the binary representation of the float represented in string tmp_str
		//printf("*ptr:%X\n",*ptr);
		/*
		if(*ptr==UINT_MAX){//detects error of conversion (likely invalid char)
			printf("Erro: char invalido na linha %d : \"%s\" de input_vectors.txt\n",i,tmp_str);
			return 4;
		}
		fwrite_retval=fwrite(ptr,sizeof(unsigned int),1,of);//writes the 32bit unsigned int
		if(fwrite_retval!=1){
			printf("Erro de fwrite!\ns");
			return 8;
		}
		*/
	}
	printf("mini_rom.vhd parsed!\n");
	fclose(fp);//closes mini_rom.vhd
	fclose(fp_types);//closes my_types.vhd

	//close output file
	fclose(of);
	printf("Arquivo \"sram_file_experimental\" gerado com sucesso!\n");
/*	free(dictionary);
	free(tmp_str);
	free(instruction_str);
	free(comment_str);
	free(ptr);
	free(s[0]);
	free(s[1]);
	free(s[2]);
	free(s[3]);
	free(s[4]);
	free(s[5]);
	free(s);*/
	return 0;
}

//function to return index of  string in dictionary names, or -1 if fails
int find(node* dict, int dict_size, char* str){
	for(int i=0;i<dict_size;i++){
		if(strcmp(str,dict[i].name)==0)
			return i;
	}
	return -1;
}

//function to convert hex strings to binary string
char* hex2bin(char* str){
	int L=strlen(str);//string length, does not count the '\0'
	char* bin_str=calloc(4*L+1,sizeof(char));
	unsigned int numeric = hex2uint(str);
	
	for(int i=0;i <= 4*L-1;i++){//goes from most significant digit to least significant (left to right)
		if(numeric & (1<<(4*L-1-i))){
			bin_str[i] = '1';
		}else{
			bin_str[i] = '0';
		}
	}
	return bin_str;
}

//function to convert hex strings to unsigned int
unsigned int hex2uint(char* str){
	unsigned int retval=0;
	int L=strlen(str);//string length, does not count the '\0'
	
	for(int i=0;i <= L-1;i++){//goes from most significant digit to least significant (left to right)
		//printf("hex2uint: i: %d L:%d char: %c\n",i,L,str[i]);
		if(str[i] >= '0' && str[i] <= '9'){//detects numeric char
			retval = 16*retval + (str[i]-'0');
		}else if(str[i] >= 'A' && str[i] <= 'F'){//detects alfabetic char (upper case)
			retval = 16*retval + (str[i]-'A'+10);
		}else if(str[i] >= 'a' && str[i] <= 'f'){//detects alfabetic char (lower case)
			retval = 16*retval + (str[i]-'a'+10);
		}else{//invalid char detected
			retval = UINT_MAX;
			return retval;
		}
	}
	//printf(" hex returns: %X ",retval);
	return retval;
}

//function to convert bin strings to unsigned int
unsigned int bin2uint(char* str){
	unsigned int retval=0;
	int L=strlen(str);//string length, does not count the '\0'
	
	for(int i=0;i <= L-1;i++){//goes from most significant digit to least significant (left to right)
		if(str[i] == '1'){//detects '1'
			retval = 2*retval + 1;
		}else{//'0' detected
			retval = 2*retval;
		}
	}
	return retval;
}
