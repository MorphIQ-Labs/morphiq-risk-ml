/* Included twice by kernels.c. See NOTICE.txt for inherited notices. */
static inline T FN(exp)(T x) {
  T k=ROUND(x*C(0x1.71547652b82fep0));
  T r=F(-k,C(0x1.a39ef35793c76p-33),F(-k,C(0x1.62e42feep-1),x));
  T a=C(0x1.93974a8c07c9dp-37);
  a=F(r,a,C(0x1.6124613a86d09p-33));
  a=F(r,a,C(0x1.1eed8eff8d898p-29));
  a=F(r,a,C(0x1.ae64567f544e4p-26));
  a=F(r,a,C(0x1.27e4fb7789f5cp-22));
  a=F(r,a,C(0x1.71de3a556c734p-19));
  a=F(r,a,C(0x1.a01a01a01a01ap-16));
  a=F(r,a,C(0x1.a01a01a01a01ap-13));
  a=F(r,a,C(0x1.6c16c16c16c17p-10));
  a=F(r,a,C(0x1.1111111111111p-7));
  a=F(r,a,C(0x1.5555555555555p-5));
  a=F(r,a,C(0x1.5555555555555p-3));
  a=F(r,a,C(0.5));
  a=F(r,a,C(1.0));
  /* For tiny x, this also returns 1+x: the perturbation rounds away. */
  return SCALE(C(1.0)+r*a,k);
}
static inline T FN(price)(T q,T low,T s,T discount,int mode) {
  T h=-(q+low);
  T numerator=C(1.0000000000594317229)-h*(C(6.1911449879694112749e-1)-h*(C(2.2180844736576013957e-1)-h*(C(4.5650900351352987865e-2)-h*(C(5.545521007735379052e-3)-h*(C(3.0717392274913902347e-4)-h*(C(4.2766597835908713583e-8)+C(8.4592436406580605619e-10)*h))))));
  T denominator=C(1.0)-h*(C(1.8724286369589162071)-h*(C(1.5685497236077651429)-h*(C(7.6576489836589035112e-1)-h*(C(2.3677701403094640361e-1)-h*(C(4.6762548903194957675e-2)-h*(C(5.5290453576936595892e-3)-C(3.0822020417927147113e-4)*h))))));
  T y=numerator/denominator;
  T sq=q*q;
  T sql=F(q,q,-sq);
  T m=((discount*s)*C(0.39894228040143267794))*y;
  T hi=C(0.5)*sq;
  T lo=C(0.5)*sql+q*low;
  T n=FLOOR(hi/C(0x1.62e42fefa39efp-1));
  T r=F(-n,C(0x1.62e42fefa39efp-1),hi)-n*C(0x1.abc9e3b39803fp-56);
  return SCALE(m*(EXP(-r,mode)*(C(1.0)-lo)),-n);
}
