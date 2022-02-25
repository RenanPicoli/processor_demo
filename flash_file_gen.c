/*
	Generates binary file for FLASH programming
	Generates a single file with 4Mx8bit data refering to data_in (input_vectors.txt) and 8Mx8bit refering to desired values (desired_vectors.txt)
	Values are 32 bit wide, but LSB are stored in address 4n, next byte in significance is stored at 4n+1, next byte is stored at 4n+2 and MSB are stored in addr 4n+3
	Example: data_in = 0x368F75BF
	addr[0]= 0xBF
	addr[1]= 0x75
	addr[2]= 0x8F
	addr[3]= 0x36
	This file will fill completely DE2-115 FLASH (8 MB),
	if there are not enough samples to fill the memory, empty spaces will be filled with zeroes.
	data_in samples and desired samples are stored aligned to the beginning of the lower and upper halves of the FLASH, respectively. 
	Resulting file will be downloaded using DE2 Control Panel
*/
//for printf, fopen, fgets, fwrite, etc.
#include <stdio.h>

//for malloc
#include <stdlib.h>

//for UINT_MAX
#include <limits.h>

//for strlen
#include <string.h>

//number of samples (pairs data_in,desired) to store
#define N_SAMPLES 0x100000

//maximum number of samples (pairs data_in,desired) that could fit inside the FLASH
// 8MB/8B=1M = 1048576 = 0x100000
#define MAX_SAMPLES 0x100000

//prototype of function to convert hex strings to unsigned int
unsigned int hex2uint(char* str);

int main(void){
	FILE *fp;//file pointer for read
	FILE *of;//file pointer for output file
	of=fopen("./flash_file","wb");//NOTE THE 'b' in "wb" mode: opens a BINARY file for write, otherwise, will put line ending chars
	if(of==NULL){
		printf("Erro ao criar o arquivo de saída!\n");
		return 1;
	}
	char tmp_str[9];//temporary string to store lines read from files
	unsigned int *ptr=malloc(1*sizeof(unsigned int));//temporary pointer to store unsigned int read from a single line of fp
	if(ptr==NULL){
		printf("Erro ao alocar a memória para o ponteiro ptr\n");
		return 6;
	}
	//printf("pointer ptr: %p\n",ptr);
	//generates lower half with data_in
	fp=fopen("./simulation/modelsim/input_vectors.txt","r");//input_vectors will only be read
	if(fp==NULL){
		printf("Erro ao ler o arquivo input_vectors.txt\n");
		return 2;
	}
	int fscanf_retval=0;//to store scanf return value to check if it was successful
	int fwrite_retval=0;//to store fwrite return value to check if it was successful
	printf("Parsing input_vectors.txt\n");
	for (int i=0;i<=N_SAMPLES-1;i++){
		//fgets((char*)tmp_str,9,fp);//reads a single line of fp, terminated with '\n', expects 8 digits (32bit data)
		fscanf_retval=fscanf(fp,"%s",tmp_str);//reads a single line of fp, with no spaces, terminated with '\n', expects 8 hexadecimal digits (32bit data)
		if(fscanf_retval!=1){
			printf("Erro ao usar fscanf na linha i=%d",i);
			return 7;
		}
		fgetc(fp);//reads and discards the newline
		tmp_str[8]='\0';
		//printf("i:%d tmp_str:%s ",i,tmp_str);
		*ptr=hex2uint(tmp_str);//stores in ptr the binary representation of the float represented in string tmp_str
		//printf("*ptr:%X\n",*ptr);
		if(*ptr==UINT_MAX){//detects error of conversion (likely invalid char)
			printf("Erro: char inválido na linha %d : \"%s\" de input_vectors.txt\n",i,tmp_str);
			return 4;
		}
		fwrite_retval=fwrite(ptr,sizeof(unsigned int),1,of);//writes the 32bit unsigned int
		if(fwrite_retval!=1){
			printf("Erro de fwrite!\n");
			return 8;
		}
	}
	fclose(fp);//closes input_vectors.txt
	if(MAX_SAMPLES > N_SAMPLES){//will pad the lower half of memory with zeroes
		for(int i=N_SAMPLES;i<=MAX_SAMPLES-1;i++){
			*ptr=0;// +0
			fwrite_retval=fwrite(ptr,sizeof(unsigned int),1,of);//writes the 32bit unsigned int
			if(fwrite_retval!=1){
				printf("Erro de fwrite!\n");
				return 8;
			}
		}
	}

	printf("Parsing desired_vectors.txt\n");
	//generates upper half with desired
	fp=fopen("./simulation/modelsim/desired_vectors.txt","r");//desired_vectors will only be read
	if(fp==NULL){
		printf("Erro ao ler o arquivo desired_vectors.txt\n");
		return 3;
	}
	for (int i=0;i<=N_SAMPLES-1;i++){
		//fgets((char*)tmp_str,9,fp);//reads a single line of fp, terminated with '\n', expects 8 digits (32bit data)
		fscanf_retval=fscanf(fp,"%s",tmp_str);//reads a single line of fp, with no spaces, terminated with '\n', expects 8 hexadecimal digits (32bit data)
		if(fscanf_retval!=1){
			printf("Erro ao usar fscanf na linha i=%d",i);
			return 7;
		}
		fgetc(fp);//reads and discards the newline
		tmp_str[8]='\0';
		//printf("i:%d tmp_str:%s ",i,tmp_str);
		*ptr=hex2uint(tmp_str);//stores in ptr the binary representation of the float represented in string tmp_str
		//printf("*ptr:%X\n",*ptr);
		if(*ptr==UINT_MAX){//detects error of conversion (likely invalid char)
			printf("Erro: char inválido na linha %d : \"%s\" de input_vectors.txt\n",i,tmp_str);
			return 4;
		}
		fwrite_retval=fwrite(ptr,sizeof(unsigned int),1,of);//writes the 32bit unsigned int
		if(fwrite_retval!=1){
			printf("Erro de fwrite!\n");
			return 8;
		}
	}
	fclose(fp);//closes desired_vectors.txt
	if(MAX_SAMPLES > N_SAMPLES){//will pad the upper half of memory with zeroes
		for(int i=N_SAMPLES;i<=MAX_SAMPLES-1;i++){
			*ptr=0;// +0
			fwrite_retval=fwrite(ptr,sizeof(unsigned int),1,of);//writes the 32bit unsigned int
			if(fwrite_retval!=1){
				printf("Erro de fwrite!\n");
				return 8;
			}
		}
	}

	//close output file
	fclose(of);
	printf("Arquivo \"flash_file\" gerado com sucesso!\n");
	return 0;
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
