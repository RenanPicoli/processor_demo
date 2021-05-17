/*
	Generates binary files for SRAM programming
	Generates a single file with 32768x16bit data refering to data_in (input_vectors.txt) and 32768x16bit bit refering to desired values (desired_vectors.txt)
	Values are 32 bit wide, but LSB are stored in address 2n, and MSB are stored in addr 2n+1
	Example: data_in = 0x368F75BF
	addr[0]= 0x75BF
	addr[1]= 0x368F
	Example: desired = 0x368F75BF
	addr[32768+0]= 0x75BF
	addr[32768+1]= 0x368F
	This file is intended for use in testbench, filling the entity tb_sram.
	tb_sram emulates a smaller version of DE2-115 SRAM
*/
//for printf, fopen, fgets, fprintf, etc.
#include <stdio.h>

//number of samples (pairs data_in,desired) to store
#define N_SAMPLES 16384
const char* header= "--DEBUG VERSION\nWIDTH=16;\nDEPTH=65536;\n\nADDRESS_RADIX=UNS;\nDATA_RADIX=HEX;\n\nCONTENT BEGIN\n";
const char* ending= "END;";

int main(void){
	FILE *fp;//file pointer for read
	FILE *of;//file pointer for outputfile
	of=fopen("./simulation/modelsim/tb_sram.mif","w");//"w" mode: opens a text file for write
	if(of==NULL){
		printf("Erro ao criar o arquivo de saída!\n");
		return 1;
	}
	char tmp_str[9];//temporary string to store content read from input file (ABCDEF12\0)
	char str_MSB[14];//string to store upper half of data to be written to outputfile (iiiiii:ABCDEF12;\n\0)
	char str_LSB[14];//string to store lower half of data to be written to outputfile (iiiiii:ABCDEF12;\n\0)
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
		sprintf(str_LSB,"%.6d:",2*i);
		fscanf_retval=fscanf(fp,"%s",tmp_str);//reads a single line of fp, with no spaces, terminated with '\n', expects 8 hexadecimal digits (32bit data)
		if(fscanf_retval!=1){
			printf("Erro ao usar fscanf na linha i=%d",i);
			return 7;
		}
		fgetc(fp);//reads and discards the newline
		str_LSB[7]=tmp_str[4];
		str_LSB[8]=tmp_str[5];
		str_LSB[9]=tmp_str[6];
		str_LSB[10]=tmp_str[7];
		str_LSB[11]=';';
		str_LSB[12]='\n';
		str_LSB[13]='\0';
		fprintf_retval=fprintf(of,"%s",str_LSB);//writes the LSB to output file
		if(fprintf_retval!=13){
			printf("Erro de fprintf!\n");
			return 8;
		}
		
		//generating MSB
		sprintf(str_MSB,"%.6d:",2*i+1);
		str_MSB[7]=tmp_str[0];
		str_MSB[8]=tmp_str[1];
		str_MSB[9]=tmp_str[2];
		str_MSB[10]=tmp_str[3];
		str_MSB[11]=';';
		str_MSB[12]='\n';
		str_MSB[13]='\0';
		fprintf_retval=fprintf(of,"%s",str_MSB);//writes the MSB to output file
		if(fprintf_retval!=13){
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
		sprintf(str_LSB,"%.6d:",2*N_SAMPLES+2*i);
		fscanf_retval=fscanf(fp,"%s",tmp_str);//reads a single line of fp, with no spaces, terminated with '\n', expects 8 hexadecimal digits (32bit data)
		if(fscanf_retval!=1){
			printf("Erro ao usar fscanf na linha i=%d",i);
			return 7;
		}
		fgetc(fp);//reads and discards the newline
		str_LSB[7]=tmp_str[4];
		str_LSB[8]=tmp_str[5];
		str_LSB[9]=tmp_str[6];
		str_LSB[10]=tmp_str[7];
		str_LSB[11]=';';
		str_LSB[12]='\n';
		str_LSB[13]='\0';
		fprintf_retval=fprintf(of,"%s",str_LSB);//writes the LSB to output file
		if(fprintf_retval!=13){
			printf("Erro de fprintf!\n");
			return 8;
		}
		
		//generating MSB
		sprintf(str_MSB,"%.6d:",2*N_SAMPLES+2*i+1);
		str_MSB[7]=tmp_str[0];
		str_MSB[8]=tmp_str[1];
		str_MSB[9]=tmp_str[2];
		str_MSB[10]=tmp_str[3];
		str_MSB[11]=';';
		str_MSB[12]='\n';
		str_MSB[13]='\0';
		fprintf_retval=fprintf(of,"%s",str_MSB);//writes the MSB to output file
		if(fprintf_retval!=13){
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
	printf("Arquivo \"tb_sram.mif\" gerado com sucesso!\n");
	return 0;
}