/*
	Generates binary files for SRAM programming
	Generates a single file with 512Kx16bit data refering to data_in (input_vectors.txt) and 512Kx16 bit refering to desired values (desired_vectors.txt)
	Values are 32 bit wide, but LSB are stored in address 2n, and MSB are stored in addr 2n+1
	Example: data_in = 0x368F75BF
	addr[0]= 0x75BF
	addr[1]= 0x368F
	This file will fill completely DE2-115 SRAM
	It will be downloaded using DE2 Control Panel
*/
//for printf, fopen, fgets, fprintf, etc.
#include <stdio.h>

//number of samples (pairs data_in,desired) to store
//256*1024 = 262144 = 0x40000
#define N_SAMPLES 0x40000
const char* header= "WIDTH=32;\nDEPTH=524288;\n\nADDRESS_RADIX=UNS;\nDATA_RADIX=HEX;\n\nCONTENT BEGIN\n";
const char* ending= "END;";

int main(void){
	FILE *fp;//file pointer for read
	FILE *of;//file pointer for outputfile
	of=fopen("./simulation/modelsim/sram.mif","w");//"w" mode: opens a text file for write
	if(of==NULL){
		printf("Erro ao criar o arquivo de saída!\n");
		return 1;
	}
	char tmp_str[17];//temporary string to store content to be written to output file
	//generates lower half with data_in
	fp=fopen("./simulation/modelsim/input_vectors.txt","r");//input_vectors will only be read
	if(fp==NULL){
		printf("Erro ao ler o arquivo input_vectors.txt\n");
		return 2;
	}
	
	int fscanf_retval=0;//to store scanf return value to check if it was successful
	int fprintf_retval=0;//to store fwrite return value to check if it was successful
	int sprintf_retval=0;//to store sprintf return value to check if it was successful
	
	//prints the header
	fprintf_retval=fprintf(of,"%s",header);//writes the header to output file
	if(fprintf_retval<0){
		printf("Erro de fprintf!\n");
		return 8;
	}
	
	printf("Parsing input_vectors.txt\n");
	for (int i=0;i<=N_SAMPLES-1;i++){
		//printf("i:%d tmp_str:%s ",i,tmp_str);
		sprintf(tmp_str,"%.6d:",i);
		fscanf_retval=fscanf(fp,"%s",tmp_str+7);//reads a single line of fp, with no spaces, terminated with '\n', expects 8 hexadecimal digits (32bit data)
		if(fscanf_retval!=1){
			printf("Erro ao usar fscanf na linha i=%d",i);
			return 7;
		}
		fgetc(fp);//reads and discards the newline
		tmp_str[15]=';';
		tmp_str[16]='\n';
		fprintf_retval=fprintf(of,"%s",tmp_str);//writes the line to output file
		if(fprintf_retval!=17){
			printf("Erro de fprintf!\n");
			return 8;
		}
	}
	fclose(fp);//closes input_vectors.txt

	printf("Parsing desired_vectors.txt\n");
	//generates upper half with desired
	fp=fopen("./simulation/modelsim/desired_vectors.txt","r");//desired_vectors will only be read
	if(fp==NULL){
		printf("Erro ao ler o arquivo desired_vectors.txt\n");
		return 3;
	}
	for (int i=0;i<=N_SAMPLES-1;i++){
		//printf("i:%d tmp_str:%s ",i,tmp_str);
		sprintf(tmp_str,"%.6d:",i+N_SAMPLES);
		fscanf_retval=fscanf(fp,"%s",tmp_str+7);//reads a single line of fp, with no spaces, terminated with '\n', expects 8 hexadecimal digits (32bit data)
		if(fscanf_retval!=1){
			printf("Erro ao usar fscanf na linha i=%d",i);
			return 7;
		}
		fgetc(fp);//reads and discards the newline
		tmp_str[15]=';';
		tmp_str[16]='\n';
		fprintf_retval=fprintf(of,"%s",tmp_str);//writes the line to output file
		if(fprintf_retval!=17){
			printf("Erro de fprintf!\n");
			return 8;
		}
	}
	fclose(fp);//closes desired_vectors.txt
	fprintf_retval=fprintf(of,"%s",ending);//writes the ending to output file
	if(fprintf_retval<0){
		printf("Erro de fprintf!\n");
		return 8;
	}

	//close output file
	fclose(of);
	printf("Arquivo \"sram.mif\" gerado com sucesso!\n");
	return 0;
}