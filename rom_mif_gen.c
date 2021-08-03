/*
	Generates mif files for data_in and desired ROM initialization
	Generates a single file with 256x32bit data refering to data_in (input_vectors.txt)
	Generates a single file with 256x32bit data refering to desired (desired_vectors.txt)
	This file will fill completely the ROM IP's
	It must be present in the directory of the memory IP's
*/
//for printf, fopen, fgets, fprintf, etc.
#include <stdio.h>

//number of samples (pairs data_in|desired) to store
//256 = 0x100
#define N_SAMPLES 0x100
const char* header= "WIDTH=32;\nDEPTH=256;\n\nADDRESS_RADIX=UNS;\nDATA_RADIX=HEX;\n\nCONTENT BEGIN\n";
const char* ending= "END;";

int main(void){
	FILE *fp;//file pointer for read
	FILE *of;//file pointer for outputfile
	of=fopen("./simulation/modelsim/data_in_rom_ip.mif","w");//"w" mode: opens a text file for write
	if(of==NULL){
		printf("Erro ao criar o arquivo de saída!\n");
		return 1;
	}
	char tmp_str[17];//temporary string to store content to be written to output file
	//reads data_in vectors
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
	fprintf_retval=fprintf(of,"%s",ending);//writes the ending to output file
	if(fprintf_retval<0){
		printf("Erro de fprintf!\n");
		return 8;
	}
	//close output file
	fclose(of);
	printf("Arquivo \"data_in_rom_ip.mif\" gerado com sucesso!\n");

	of=fopen("./simulation/modelsim/desired_rom_ip.mif","w");//"w" mode: opens a text file for write
	if(of==NULL){
		printf("Erro ao criar o arquivo de saída!\n");
		return 1;
	}
	
	//prints the header
	fprintf_retval=fprintf(of,"%s",header);//writes the header to output file
	if(fprintf_retval<0){
		printf("Erro de fprintf!\n");
		return 8;
	}
	printf("Parsing desired_vectors.txt\n");
	//generates upper half with desired
	fp=fopen("./simulation/modelsim/desired_vectors.txt","r");//desired_vectors will only be read
	if(fp==NULL){
		printf("Erro ao ler o arquivo desired_vectors.txt\n");
		return 3;
	}
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
	fclose(fp);//closes desired_vectors.txt
	fprintf_retval=fprintf(of,"%s",ending);//writes the ending to output file
	if(fprintf_retval<0){
		printf("Erro de fprintf!\n");
		return 8;
	}
	//close output file
	fclose(of);
	printf("Arquivo \"desired_rom_ip.mif\" gerado com sucesso!\n");

	of=fopen("./simulation/modelsim/output_rom_ip.mif","w");//"w" mode: opens a text file for write
	if(of==NULL){
		printf("Erro ao criar o arquivo de saída!\n");
		return 1;
	}
	
	//prints the header
	fprintf_retval=fprintf(of,"%s",header);//writes the header to output file
	if(fprintf_retval<0){
		printf("Erro de fprintf!\n");
		return 8;
	}
	printf("Parsing output_vectors.txt\n");
	//generates upper half with desired
	fp=fopen("./simulation/modelsim/output_vectors.txt","r");//desired_vectors will only be read
	if(fp==NULL){
		printf("Erro ao ler o arquivo output_vectors.txt\n");
		return 3;
	}
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
	fclose(fp);//closes output_vectors.txt
	fprintf_retval=fprintf(of,"%s",ending);//writes the ending to output file
	if(fprintf_retval<0){
		printf("Erro de fprintf!\n");
		return 8;
	}
	//close output file
	fclose(of);
	printf("Arquivo \"output_rom_ip.mif\" gerado com sucesso!\n");
	
	return 0;
}