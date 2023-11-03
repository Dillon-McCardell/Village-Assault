// Fill out your copyright notice in the Description page of Project Settings.


#include "TerrainGenerator.h"

// Sets default values
ATerrainGenerator::ATerrainGenerator()
{
 	// Set this actor to call Tick() every frame.  You can turn this off to improve performance if you don't need it.
	PrimaryActorTick.bCanEverTick = false;

}

// Called when the game starts or when spawned
void ATerrainGenerator::BeginPlay()
{
	Super::BeginPlay();
	//GenerateMapOutline();
	GenerateTerrain();

}

// Called every frame
void ATerrainGenerator::Tick(float DeltaTime)
{
	Super::Tick(DeltaTime);

}

void ATerrainGenerator::GenerateTerrain()
{
	int TileSize = 32;
	int SpawnPadWidth = 3;
	int SpawnPadHeight = FMath::RandRange(5,MapHeight-10);
	int TileZLocation = 0;
	TArray<int> GrassZLocationArray;
	//Spawn left base pad
	for (int i = 0; i < SpawnPadWidth; i++) {
		FVector Location(i*TileSize, 30.0f, SpawnPadHeight*TileSize);
		GetWorld()->SpawnActor<AActor>(GrassMiddle, Location, FRotator::ZeroRotator);
		for (int z = SpawnPadHeight-1; z > 0; z--) {
			Location = FVector(i * TileSize, 30.0f, z * TileSize);
			GetWorld()->SpawnActor<AActor>(Dirt, Location, FRotator::ZeroRotator);
		}
	}
	//Spawn left base
	FVector LeftBaseLocation(-20.0f, 30.0f, (SpawnPadHeight + 3.75) * TileSize);
	GetWorld()->SpawnActor<AActor>(PlayerBase, LeftBaseLocation, FRotator::ZeroRotator);

	//First generate the grass layer
	FVector PrevSpawnLocation((SpawnPadWidth-1)*TileSize, 30, SpawnPadHeight*TileSize);
	for (int i = 0; i < MapWidth-(SpawnPadWidth*2); i++) {
		int TileHeightJump = 1;
		if (FMath::RandRange(0, Noise) == 0) {
			TileHeightJump = FMath::RandRange(1, Topography);
		}
		int TileHeightChange = FMath::RandRange(-1, 1) * TileHeightJump;
		if ((PrevSpawnLocation.Z / TileSize) + TileHeightChange > MapHeight-4) {
			TileZLocation = (MapHeight-4) * TileSize;
		}
		else if ((PrevSpawnLocation.Z / TileSize) + TileHeightChange < 3) {
			TileZLocation = 3 * TileSize;
		}
		else {
			TileZLocation = PrevSpawnLocation.Z + TileHeightChange * TileSize;
		}
		GrassZLocationArray.Add(TileZLocation);
		FVector Location(PrevSpawnLocation.X+TileSize, PrevSpawnLocation.Y, TileZLocation);
		GetWorld()->SpawnActor<AActor>(GrassMiddle, Location, FRotator::ZeroRotator);
		PrevSpawnLocation = Location;
	}
	//Fill ground underneath grass with Dirt tiles
	int Start = (SpawnPadWidth) * TileSize;
	for (int i = 0; i < MapWidth - (SpawnPadWidth * 2); i++) {
		for (int z = GrassZLocationArray[i]/TileSize; z > 1; z--) {
			FVector Location(Start + (TileSize * i), 30.0f, GrassZLocationArray[i] - ((z-1) * TileSize));
			GetWorld()->SpawnActor<AActor>(Dirt, Location, FRotator::ZeroRotator);
		}
	}
	//Fill space above grass with Air tiles
	for (int i = 0; i < MapWidth - (SpawnPadWidth * 2); i++) {
		for (int z = 1; z < MapHeight - (GrassZLocationArray[i] / TileSize); z++) {
			FVector Location(Start + (TileSize * i), 30.0f, GrassZLocationArray[i] + (z * TileSize));
			GetWorld()->SpawnActor<AActor>(Air, Location, FRotator::ZeroRotator);
		}
	}
	
	//Spawn right base platform
	int RightSpawnPadHeight = FMath::RandRange((PrevSpawnLocation.Z/TileSize) - 1, (PrevSpawnLocation.Z/TileSize) + 1);
	for (int i = 0; i < SpawnPadWidth; i++) {
		FVector Location(PrevSpawnLocation.X+(i*TileSize)+TileSize, 30.0f, RightSpawnPadHeight*TileSize);
		GetWorld()->SpawnActor<AActor>(GrassMiddle, Location, FRotator::ZeroRotator);
		for (int z = RightSpawnPadHeight-1; z > 0; z--) {
			Location = FVector(PrevSpawnLocation.X + (i * TileSize)+TileSize, 30.0f, z * TileSize);
			GetWorld()->SpawnActor<AActor>(Dirt, Location, FRotator::ZeroRotator);
		}
	}
	//Spawn right base
	FVector RightBaseLocation(PrevSpawnLocation.X+12, 30.0f, (RightSpawnPadHeight + 3.75) * TileSize);
	GetWorld()->SpawnActor<AActor>(PlayerBase, RightBaseLocation, FRotator::ZeroRotator);
}

void ATerrainGenerator::GenerateMapOutline() {
	int TileSize = 32;
	for (int i = 0; i < MapWidth; i++) {
		FVector Location(i * TileSize, 30.0f, MapHeight * TileSize);
		GetWorld()->SpawnActor<AActor>(Dirt, Location, FRotator::ZeroRotator);
		Location = FVector(i * TileSize, 30.0f, 0.0f);
		GetWorld()->SpawnActor<AActor>(Dirt, Location, FRotator::ZeroRotator);

	}
}
