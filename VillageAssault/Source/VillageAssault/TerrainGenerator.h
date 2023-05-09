// Fill out your copyright notice in the Description page of Project Settings.

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Math/UnrealMathUtility.h"
#include "TerrainGenerator.generated.h"

UCLASS()
class VILLAGEASSAULT_API ATerrainGenerator : public AActor
{
	GENERATED_BODY()
	
public:	
	// Sets default values for this actor's properties
	ATerrainGenerator();

protected:
	// Called when the game starts or when spawned
	virtual void BeginPlay() override;

public:	
	// Called every frame
	virtual void Tick(float DeltaTime) override;

	void GenerateTerrain();
	void GenerateMapOutline();
	void GenerateTerrainHeights(float* Heights, int32 Length, float MinHeight, float MaxHeight, float Frequency, int32 Octaves);

	UPROPERTY(EditDefaultsOnly, Category = "Assets")
		TSubclassOf<AActor> GrassMiddle;
	UPROPERTY(EditDefaultsOnly, Category = "Assets")
		TSubclassOf<AActor> Dirt;
	UPROPERTY(EditDefaultsOnly, Category = "Assets")
		TSubclassOf<AActor> Air;
	UPROPERTY(EditDefaultsOnly, Category = "Assets")
		TSubclassOf<AActor> Brick;
	UPROPERTY(EditDefaultsOnly, Category = "Assets")
		TSubclassOf<AActor> PlayerBase;

	UPROPERTY(EditDefaultsOnly, Category = "Map")
		int MapHeight;
	UPROPERTY(EditDefaultsOnly, Category = "Map")
		int MapWidth;
	UPROPERTY(EditDefaultsOnly, Category = "Map")
		int Topography;
	UPROPERTY(EditDefaultsOnly, Category = "Map")
		int Noise;

};
