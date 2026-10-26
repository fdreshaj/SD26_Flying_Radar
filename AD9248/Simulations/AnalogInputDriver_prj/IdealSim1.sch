<Qucs Schematic 26.1.1>
<Properties>
  <View=-145,-163,1108,604,1,0,0>
  <Grid=10,10,1>
  <DataSet=IdealSim1.dat>
  <DataDisplay=IdealSim1.dpl>
  <OpenDisplay=0>
  <Script=IdealSim1.m>
  <RunScript=0>
  <showFrame=0>
  <FrameText0=Title>
  <FrameText1=Drawn By:>
  <FrameText2=Date:>
  <FrameText3=Revision:>
</Properties>
<Symbol>
</Symbol>
<Components>
  <C C1 1 370 210 17 -26 0 1 "1 nF" 1 "" 0 "neutral" 0>
  <C C2 1 280 30 -26 -61 0 2 "1 nF" 1 "" 0 "neutral" 0>
  <OpAmp OP1 1 500 150 -26 42 0 0 "1e6" 1 "15 V" 0>
  <GND * 1 370 260 0 0 0 0>
  <Vac V1 1 60 230 18 -26 0 1 "1 V" 1 "1 kHz" 0 "0" 0 "0" 0 "0" 0 "0" 0>
  <GND * 1 60 290 0 0 0 0>
  <R R2 1 280 130 -26 15 0 0 ".33 kOhm" 1 "26.85" 0 "0.0" 0 "0.0" 0 "26.85" 0 "US" 0>
  <R R1 1 140 130 -26 15 0 0 ".33 kOhm" 1 "26.85" 0 "0.0" 0 "0.0" 0 "26.85" 0 "US" 0>
  <VProbe Pr1 1 590 -10 28 -31 0 0>
  <GND * 1 600 40 0 0 0 0>
  <.AC AC1 1 170 240 0 34 0 0 "log" 1 "1 Hz" 1 "10000 kHz" 1 "354" 1 "no" 0>
  <NutmegEq NutmegEq1 1 460 340 -30 18 0 0 "ALL" 1 "Response=db(v(Pr1)/v(V1))" 1>
</Components>
<Wires>
  <470 170 450 170 "" 0 0 0 "">
  <450 170 450 280 "" 0 0 0 "">
  <540 150 580 150 "" 0 0 0 "">
  <450 280 580 280 "" 0 0 0 "">
  <580 280 580 150 "" 0 0 0 "">
  <310 130 370 130 "" 0 0 0 "">
  <250 30 210 30 "" 0 0 0 "">
  <210 30 210 130 "" 0 0 0 "">
  <170 130 210 130 "" 0 0 0 "">
  <210 130 250 130 "" 0 0 0 "">
  <370 240 370 260 "" 0 0 0 "">
  <470 130 370 130 "" 0 0 0 "">
  <370 180 370 130 "" 0 0 0 "">
  <60 200 60 130 "" 0 0 0 "">
  <110 130 60 130 "" 0 0 0 "">
  <60 260 60 290 "" 0 0 0 "">
  <580 30 580 150 "" 0 0 0 "">
  <580 30 310 30 "" 0 0 0 "">
  <580 10 580 30 "" 0 0 0 "">
  <600 10 600 40 "" 0 0 0 "">
  <60 130 60 130 "V1" 10 110 0 "">
</Wires>
<Diagrams>
  <Rect 730 250 240 160 3 #c0c0c0 1 10 1 1 1 1e+07 1 -60 20 5.26878 1 -1 1 1 315 0 225 1 0 0 "Freq (Hz)" "Magnitude (dB)" "">
	<"ngspice/ac.response" #0000ff 0 3 0 0 0>
  </Rect>
</Diagrams>
<Paintings>
</Paintings>
