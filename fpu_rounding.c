#include <fenv.h>
#pragma STDC FENV_ACCESS ON

#include <stdio.h>

int main (){

	// store the original rounding mode
	const int originalRounding = fegetround( );

	printf("FPU Rounding is %d\n",originalRounding);
 	return 0;
}
